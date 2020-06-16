Imports Microsoft.Graph
Imports System.Net.Http.Headers

    Async Function GetGraphApiClientApp() As Threading.Tasks.Task(Of GraphServiceClient)

        Dim clientID = "9d4be979-3f0c-4056-a523-972d144ceda1" ' Azure AD App ID
        Dim appSecret = "b6;9gx2NEPpFKi~1v_JUh9o00Q.77Q10O-"
        Dim domain = "myaztenant.onmicrosoft.com"

        Dim credentials = New Microsoft.IdentityModel.Clients.ActiveDirectory.ClientCredential(clientID, appSecret)
        Dim authContext = New Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext("https://login.microsoftonline.com/" + domain + "/")
        Dim token = Await authContext.AcquireTokenAsync("https://graph.microsoft.com/", credentials)
        Dim AccessToken = token.AccessToken

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