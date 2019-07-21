<#
.SYNOPSIS
  Gets a list of all recently created resources across all subscriptions that have the Tag: $TagName and send an email report.
    
.DESCRIPTION
    This script is hosted in an Azure Automation account.
    It checks the date on the Tag: $TagName and works out who created the resource from Azure Monitor Logs and then estimates the consumption cost based on the last day's runtime.
.INPUTS
  None
.OUTPUTS
  Logs stored in Azure Automation
.NOTES
  Version:        0.1
  Author:         Jack Rudlin
  Creation Date:  05/06/19
  Purpose/Change: Initial script development

  Version:        0.2
  Author:         Jack Rudlin
  Creation Date:  15/06/19
  Purpose/Change: Fixed cost by limited date and select First 1
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
#$ErrorActionPreference = "SilentlyContinue"


#----------------------------------------------------------[Declarations]----------------------------------------------------------


$TagName = "CreatedOnDate"
$GlobalAdminAccount = "AzReadOnlyAccount@domain.co.uk"
$GetAdditionalLogBased = $false
$CultureGB = New-Object System.Globalization.CultureInfo("en-GB")

$DaysAgo = -2
#$DaysAgo = -7
$StartDate = ((Get-Date -DisplayHint Date).Date).AddDays($DaysAgo)

$DaysUntil = $DaysAgo+1
#$DaysUntil = -1
$EndDate = ((Get-Date -DisplayHint Date).Date).AddDays($DaysUntil)

# Email report config
$EmailRecipients = "Jack.Rudlin@domain.co.uk","Jack.Test@domain.org.uk"
$EmailSubject = "Azure Resources Reports"

# SendGrid
$AutomationAccount = 'Azure Automation Account Name'
$AutomationAccountRG = 'Azure Automation Account RG'
$Runbook = 'Email-SendGrid'

#-----------------------------------------------------------[Functions]------------------------------------------------------------
Function Email-SendGrid {
    [CmdletBinding()]
        Param(
            [parameter(Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            $EmailBody,
            [parameter(Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            $ToEmailAddress,
            [parameter(Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            $Subject
        )

    # Ensures you do not inherit an AzureRMContext in your runbook
    Disable-AzContextAutosave –Scope Process

    # Connect to Azure with RunAs account
    $ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'

    Add-AzAccount `
        -ServicePrincipal `
        -Tenant $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint

    # Set the subscription context
    $AzureContext = Set-AzContext -SubscriptionId $ServicePrincipalConnection.SubscriptionID | Out-Null

    $params = @{"EmailBody"=$EmailBody;"EmailAddress"=$ToEmailAddress;"EmailSubject"=$Subject}

    Start-AzAutomationRunbook `
        –AutomationAccountName $AutomationAccount `
        –Name $Runbook `
        -ResourceGroupName $AutomationAccountRG `
        -DefaultProfile $AzureContext `
        –Parameters $params -wait

}

#-----------------------------------------------------------[Script]------------------------------------------------------------

# Get Read Only account for secure vault
try{
    $Creds = Get-AutomationPSCredential -Name $ROAccount
    Write-output -inputobject "Got account creds for: [$ROAccount]"
} Catch {
    write-error -Message "Could not get creds for account: [$ROAccount] $_"
    return
}


If(-not(Get-AzContext)){
    Write-output -inputobject "Connecting AzAccount"
    Connect-AzAccount -Credential $Creds
}

import-module Az.Billing
Get-AzSubscription
$EnabledSubs = Get-AzSubscription | where-object -Property "state" -eq "Enabled"

write-output -InputObject "`nUsing date range from: [$StartDate] to: [$EndDate]"

$OutputList = New-Object System.Collections.ArrayList
#$OutputList = [PSCustomObject]@{}
If($EnabledSubs.Count -gt 0){
    ForEach($Sub in $EnabledSubs){
        
        # Set the subscription context
        Set-AzContext -SubscriptionId $Sub.Id | Out-Null
        
        # Get resources from Azure Monitor Logs so that we can use this info to retrieve the user who created the resource.
        write-output -InputObject "`nGetting log based resources in subscription: [$($Sub.Name)] between: [$StartDate] and: [$EndDate]"
        $AllLogs = Get-AzLog -StartTime $StartDate -EndTime $EndDate -Status "Succeeded" -WarningAction "SilentlyContinue"
        write-output -InputObject "All logs count: [$($AllLogs.Count)]"    
        $FilteredLogs = $AllLogs `
            | select SubmissionTimestamp, ResourceID, Caller, @{Name="OperationNamelocalizedValue"; Expression={$_.OperationName.localizedValue}}, @{Name="StatusValue"; Expression={$_.Status.Value}}, @{Name="OperationNameValue"; Expression={$_.OperationName.Value}}, @{Name="HttpVerb"; Expression={$_.HttpRequest.Method}}, @{Name="EventNameValue"; Expression={$_.EventName.Value}} `
            | Where-Object -FilterScript {$_.EventNameValue -EQ "EndRequest" -and $_.OperationNameValue -notlike "*audit*" -and $_.HttpVerb -ne "PATCH" -and $_.OperationNameValue -like "*write" -and $_.OperationNamelocalizedValue -notlike "Update *" -and $_.OperationNamelocalizedValue -notlike "*role assignment*"}
        write-output -InputObject "FilteredLogs logs count: [$($FilteredLogs.Count)]"
        $UniqueFilteredLogs = $FilteredLogs | Sort-Object -Property ResourceId -Unique
        write-output -InputObject "UniqueFilteredLogs logs count: [$($UniqueFilteredLogs.Count)]"

        # Get resources with CreatedOnDate tag
        write-output -InputObject "`nGetting tagged resources in subscription: [$($Sub.Name)] with Tag: [$TagName]."
        $Tagged = Get-AzResource -TagName $TagName
        write-output -InputObject "[$($Tagged.Count)] tagged resources retrieved."

        # Remove tags with the 'Original' value
        $TaggedNotOriginal = $Tagged | Where-Object -FilterScript { $_.Tags.CreatedOnDate -ne "Original"}
        write-output -InputObject "[$($TaggedNotOriginal.Count)] tagged resources with a date retrieved."

        # Loop through all the filtered resources
        ForEach($TaggedResource in $TaggedNotOriginal){
            write-output -InputObject "`nChecking resource: [$($TaggedResource.Name)]"
            $ResourceDate = Get-Date $TaggedResource.Tags.CreatedOnDate

            If(($ResourceDate -gt $StartDate) -and ($ResourceDate -lt $EndDate)){
                write-output -InputObject "Resource was created on: [$ResourceDate]"          
                write-output -InputObject "Type: [$($TaggedResource.Type)], Location: [$($TaggedResource.Location)]"
                $Log = $UniqueFilteredLogs | Where-Object -FilterScript {$_.ResourceID -eq $TaggedResource.ResourceId}
                
                write-output -InputObject "CreatedBy: [$($Log.Caller)]"

                #Try and get cost:
                $CostObject = $null
                $Cost = $null
                $parent = $null

                $CostObject = Get-AzConsumptionUsageDetail -InstanceName $TaggedResource.ResourceName -StartDate $StartDate -EndDate $EndDate `
                                | Sort-Object -Property UsageQuantity -Descending `
                                | Select -First 1
                If($CostObject){
                    $Cost = ($CostObject.PretaxCost | Measure-Object -Sum).Sum
                } else {
                    
                    # Gets cost of parent resource - this may then produce reports with duplicates
                    # If($TaggedResource.ParentResource -like "*/*"){
                    #     $Parent = Split-Path -Path $TaggedResource.ParentResource -Leaf
                    # } elseif($TaggedResource.ParentResource) {
                    #     $Parent = $TaggedResource.ParentResource
                    # }

                    # If($Parent){
                    #     $CostObject = Get-AzConsumptionUsageDetail -InstanceName $Parent -StartDate $StartDate -EndDate $EndDate `
                    #             | Sort-Object -Property UsageQuantity -Descending `
                    #             | Select -First 1
                    #     $Cost = ($CostObject.PretaxCost | Measure-Object -Sum).Sum
                    # }

                }
                
                If($Cost.Count -gt 0){
                    $CostPerMonth = [math]::Round($($Cost * 365) / 12,2)
                } else {
                    $CostPerMonth = "Could not obtain pricing info or likely free."
                }
                
                Write-Output -InputObject "Estimated cost per month: [£$($CostPerMonth)]"
                
                $OutputList.Add( (New-Object -TypeName PSObject -Property @{`
                    "CreationDate"="$((Get-Date $ResourceDate).toString("dd/MM/yyyy HH:mm:ss", $CultureGB))";
                    "Resource"="$($TaggedResource.ResourceName)"
                    "Type"="$($TaggedResource.Type)";
                    "Location"="$($TaggedResource.Location)";
                    "CreatedBy"="$($Log.Caller)";
                    "Cost"="$CostPerMonth";
                }) ) | Out-Null

            } else {
                write-output -InputObject "Resource out of date range because of: [$ResourceDate]"
            }



        } 
        

    }

    If($OutputList.Count -gt 0){

$Header = @"
<style>
TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED;}
TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
</style>
"@

        #$OutputList | ConvertTo-Html -Head $Header | Out-File -FilePath c:\temp\PoshHTML.html -Force -Confirm:$false
        $Body = [string]($OutputList | ConvertTo-Html -Head $Header)
        
        Email-SendGrid `
            -EmailBody $Body `
            -ToEmailAddress $EmailRecipients `
            -Subject $EmailSubject

    } else {
        # No new resources. Send an email as such.
        Email-SendGrid `
            -EmailBody "No new resources created between: [$(Get-Date $StartDate -Format "dd/MM/yy HH:mm:ss")] and [$(Get-Date $EndDate -Format "dd/MM/yy HH:mm:ss")]." `
            -ToEmailAddress $EmailRecipients `
            -Subject $EmailSubject
    }


    If($GetAdditionalLogBased){

        write-output -InputObject "`nGetting log based resources in subscription: [$($Sub.Name)] between: [$StartDate] and: [$EndDate]"
        $AllLogs = Get-AzLog -StartTime $StartDate -EndTime $EndDate -Status "Succeeded" -WarningAction "SilentlyContinue"
        write-output -InputObject "All logs count: [$($AllLogs.Count)]"
        
        $FilteredLogs = $AllLogs `
            | select SubmissionTimestamp, ResourceID, Caller, @{Name="OperationNamelocalizedValue"; Expression={$_.OperationName.localizedValue}}, @{Name="StatusValue"; Expression={$_.Status.Value}}, @{Name="OperationNameValue"; Expression={$_.OperationName.Value}}, @{Name="HttpVerb"; Expression={$_.HttpRequest.Method}}, @{Name="EventNameValue"; Expression={$_.EventName.Value}} `
            | Where-Object -FilterScript {$_.EventNameValue -EQ "EndRequest" -and $_.OperationNameValue -notlike "*audit*" -and $_.HttpVerb -ne "PATCH" -and $_.OperationNameValue -like "*write" -and $_.OperationNamelocalizedValue -notlike "Update *" -and $_.OperationNamelocalizedValue -notlike "*role assignment*"}
        write-output -InputObject "FilteredLogs logs count: [$($FilteredLogs.Count)]"

        $UniqueFilteredLogs = $FilteredLogs | Sort-Object -Property ResourceId -Unique
        write-output -InputObject "UniqueFilteredLogs logs count: [$($UniqueFilteredLogs.Count)]"

        $RemovedTagged_UniqueFilteredLogs = $UniqueFilteredLogs | Where-Object -FilterScript {$TaggedNotOriginal.ResourceID -notcontains $_.ResourceID}
        write-output -InputObject "RemovedTagged_UniqueFilteredLogs logs count: [$($RemovedTagged_UniqueFilteredLogs.Count)]"

        ForEach($Log in $UniqueFilteredLogs){
            
                    $res = $null
                    
                    $res = Get-AzResource -ResourceId $Log.ResourceId -ErrorAction SilentlyContinue
                    #write-output -InputObject "Error var: $ErrorVar"
                If($res.resourceid){
                    
                    write-output -InputObject "`n$($Log.Caller)"
                    write-output -InputObject "Details: [$($res.Name) $($res.ResourceGroupName) $($res.Location) $($res.Kind)]"
                    write-output -InputObject "----------------------------------------------------"
                } else {
                    #Write-Warning -Message "Resource no longer exists: [$($Log.ResourceId)]"
                }
        }

    }

} else {
    Write-Error -Message "Could not find any enabled subscriptions."
}