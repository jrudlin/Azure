
    Public Async Function DeleteMessage(ByVal MessageID As String) As Threading.Tasks.Task(Of Boolean)
        Try
            Dim GraphClient = GetGraphApiClientApp().Result

            ' Get the details of the user who is connected to the Graph
            'Dim MeUser = Await GraphClient.Me.Request().GetAsync()

            ' Get all users in the Azure Active Directory
            'Dim users = Await GraphClient.Users.Request().GetAsync()

            Await GraphClient.Users("user1@tenant.org.uk").MailFolders.Request().Filter("displayName eq 'Saved'").GetAsync()

            ' Delete the email specified by MessageID from the office mailbox
            Await GraphClient.Users("user1@tenant.org.uk").Messages(MessageID).Request().DeleteAsync()
            Return True
        Catch e As Exception
            Return False
        End Try

    End Function