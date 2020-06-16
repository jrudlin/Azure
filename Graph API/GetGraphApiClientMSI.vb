Imports Microsoft.Azure.Services.AppAuthentication
Imports Microsoft.Graph
Imports System.Net.Http.Headers

    Async Function GetGraphApiClientMSI() As Threading.Tasks.Task(Of GraphServiceClient)

        Dim azureServiceTokenProvider = New AzureServiceTokenProvider()
        Dim AccessToken As String = Await azureServiceTokenProvider.GetAccessTokenAsync("https://graph.microsoft.com/")

        Dim GraphServiceClient = New GraphServiceClient(
            New DelegateAuthenticationProvider(
                Function(requestMessage)
                    requestMessage.Headers.Authorization = New AuthenticationHeaderValue("bearer", AccessToken)
                    Return Threading.Tasks.Task.CompletedTask
                End Function
            )
        )

        Return GraphServiceClient

    End Function