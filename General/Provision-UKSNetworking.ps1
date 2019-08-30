# Global variables
$SubscriptionName = "Prod Subscription"

$Location = "uksouth"
$RG_ER_Name = "rg-ExpressRoute-Prod-1"

$VNETName = "VNET-PROD-1"
$VNETAddress = "172.101.0.0/16"
$RG_VNET_Name = "rg-VNET-Prod-1"

$Subnet1 = "Subnet-Legacy-Prod-1"
$Subnet1Address = "172.101.200.0/24"
$Subnet2 = "Subnet-Production-Prod-1"
$Subnet2Address = "172.101.1.0/24"
$Subnet3 = "Subnet-Development-Prod-1"
$Subnet3Address = "172.101.3.0/24"
$Subnet4 = "Subnet-VDI-Prod-1"
$Subnet4Address = "172.101.2.0/24"
$Subnet5 = "Subnet-Management-Prod-1"
$Subnet5Address = "172.101.0.0/24"

$GWSubnetAddress = "172.101.255.0/24"
$GWIPName = "PIP-GWSubnet-Prod-1"
$GWIPconfName = "IPConf-GWSubnet-Prod-1"
$GWName = "GW-Prod-1"

$ERName = "ExpressRoute-Prod-1"

$RG_NSG_Name = "rg-NSG-Prod-1"

# Connect to Az with a contributor level account to the Prod subscription
Connect-AzAccount

# Set the correct subscription
Set-AzContext -SubscriptionName $SubscriptionName

# 1 - Create the VNET and Resource Groups
New-AzResourceGroup -Name $RG_VNET_Name -Location $Location

$VNET = New-AzVirtualNetwork `
  -ResourceGroupName $RG_VNET_Name `
  -Location $Location `
  -Name $VNETName `
  -AddressPrefix $VNETAddress


# 2 Create the NSGs for the Subnets
New-AzResourceGroup -Name $RG_NSG_Name -Location $Location
$AsgAllServers = New-AzApplicationSecurityGroup `
  -ResourceGroupName $RG_NSG_Name `
  -Name "ASG-AllServers-Prod-1" `
  -Location $Location

$AsgMgmt = New-AzApplicationSecurityGroup `
  -ResourceGroupName $RG_NSG_Name `
  -Name "ASG-Management-Prod-1" `
  -Location $Location

$mgmtRuleOut = New-AzNetworkSecurityRuleConfig `
  -Name "Allow-Mgmt-All-Outbound" `
  -Access Allow `
  -Protocol * `
  -Direction Outbound `
  -Priority 110 `
  -SourceApplicationSecurityGroupId $AsgMgmt.id `
  -SourcePortRange * `
  -DestinationApplicationSecurityGroupId $AsgAllServers.id `
  -DestinationPortRange *

$mgmtRuleIn = New-AzNetworkSecurityRuleConfig `
  -Name "Allow-Mgmt-All-Inbound" `
  -Access Allow `
  -Protocol * `
  -Direction Inbound `
  -Priority 111 `
  -SourceApplicationSecurityGroupId $AsgMgmt.id `
  -SourcePortRange * `
  -DestinationApplicationSecurityGroupId $AsgAllServers.id `
  -DestinationPortRange *

$MgmtNSG = New-AzNetworkSecurityGroup `
  -ResourceGroupName $RG_NSG_Name `
  -Location $Location `
  -Name "NSG-Mgmt-Prod-1" `
  -SecurityRules $mgmtRuleOut


# 3 Create the Subnets
$subnetConfig1 = Add-AzVirtualNetworkSubnetConfig `
  -Name $Subnet1 `
  -AddressPrefix $Subnet1Address `
  -VirtualNetwork $VNET `
  -NetworkSecurityGroup $MgmtNSG

$subnetConfig2 = Add-AzVirtualNetworkSubnetConfig `
  -Name $Subnet2 `
  -AddressPrefix $Subnet2Address `
  -VirtualNetwork $VNET `
  -NetworkSecurityGroup $MgmtNSG

$subnetConfig3 = Add-AzVirtualNetworkSubnetConfig `
  -Name $Subnet3 `
  -AddressPrefix $Subnet3Address `
  -VirtualNetwork $VNET `
  -NetworkSecurityGroup $MgmtNSG

$subnetConfig4 = Add-AzVirtualNetworkSubnetConfig `
  -Name $Subnet4 `
  -AddressPrefix $Subnet4Address `
  -VirtualNetwork $VNET `
  -NetworkSecurityGroup $MgmtNSG

$subnetConfig5 = Add-AzVirtualNetworkSubnetConfig `
  -Name $Subnet5 `
  -AddressPrefix $Subnet5Address `
  -VirtualNetwork $VNET `
  -NetworkSecurityGroup $MgmtNSG

$VNET | Set-AzVirtualNetwork


# 4 Create the Gateway Subnet and the Gateway for the VNET
# GW Subnet
Add-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $VNET -AddressPrefix $GWSubnetAddress
$VNET | Set-AzVirtualNetwork
# VNET GW
$GWSubnet = Get-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $VNET
$GWPIP = New-AzPublicIpAddress -Name $GWIPName -ResourceGroupName $RG_VNET_Name -Location $Location -AllocationMethod Dynamic
$GWIPConf = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $GWSubnet -PublicIpAddress $GWPIP
New-AzVirtualNetworkGateway -Name $GWName -ResourceGroupName $RG_VNET_Name -Location $Location -IpConfigurations $GWIPConf -GatewayType Expressroute -GatewaySku Standard

# 5 Create the ExpressRoute Circuit https://docs.microsoft.com/en-us/azure/expressroute/expressroute-howto-circuit-arm
New-AzResourceGroup -Name $RG_ER_Name -Location $Location

New-AzExpressRouteCircuit `
    -Name $ERName `
    -ResourceGroupName $RG_ER_Name `
    -Location $Location `
    -SkuTier Standard `
    -SkuFamily MeteredData `
    -ServiceProviderName "Equinix" `
    -PeeringLocation "London" `
    -BandwidthInMbps 1000

# 6 Azure Private Peering ? https://docs.microsoft.com/en-us/azure/expressroute/expressroute-howto-routing-arm#private
$ERCircuit = Get-AzExpressRouteCircuit -Name $ERName -ResourceGroupName $RG_ER_Name

# ASN and VLANID provided by Claranet
Add-AzExpressRouteCircuitPeeringConfig -Name "AzurePrivatePeering" `
  -ExpressRouteCircuit $ERCircuit `
  -PeeringType AzurePrivatePeering `
  -PeerASN 8426 `
  -PrimaryPeerAddressPrefix "172.100.0.0/30" `
  -SecondaryPeerAddressPrefix "172.100.0.4/30" `
  -VlanId 10

Set-AzExpressRouteCircuit -ExpressRouteCircuit $ERCircuit

# 7 Peer the VNET to the Gateway/ER
$ERCircuit = Get-AzExpressRouteCircuit -Name $ERName -ResourceGroupName $RG_ER_Name
$GW = Get-AzVirtualNetworkGateway -Name $GWName -ResourceGroupName $RG_VNET_Name
$GWConnection = New-AzVirtualNetworkGatewayConnection `
    -Name "ERGW-Connection-Prod-1" `
    -ResourceGroupName $RG_ER_Name `
    -Location $Location `
    -VirtualNetworkGateway1 $GW `
    -PeerId $ERCircuit.Id `
    -ConnectionType ExpressRoute