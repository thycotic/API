<# 
 .Synopsis
  Create new Secret Server local users and email them login information.

 .Parameter UserListPath
  The Location of the User List Csv (Username,EmailAddress)

 .Parameter SecretServerRoot
  The Secret Server Root Url

 .Parameter SecretServerUsername
  The Secret Server Auth Username

 .Parameter SecretServerPassword
  The Secret Server Auth Password

 .Parameter SecretServerUserDomain
  The Secret Server Auth Domain. Optional
  
 .Parameter SmtpServer
  The Smtp Server

 .Parameter SmtpUserName
  The Smtp Username

 .Parameter SmtpPassword
  The Smtp Password

 .Example 
 Tss-Create-User-Email -users userList.csv -secretServerRoot https://ambarco.com/SecretServer `
 -secretServerUsername admin@ambarco.com -secretServerUserPassword <PASSWORD> -smtpServer <SMTP_SERVER> `
 -smtpUserName <SMTP_USERNAME> -smtpPassword <SMTP_PASSWORD>
#>
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
function Tss-Create-User-Email {
    param(
         [Parameter(Mandatory)]$userListPath
        ,[Parameter(Mandatory)]$secretServerRoot
        ,[Parameter(Mandatory)]$secretServerUsername
        ,[Parameter(Mandatory)]$secretServerUserPassword
        ,$secretServerUserDomain
        ,[Parameter(Mandatory)]$smtpServer
        ,[Parameter(Mandatory)]$smtpUserName
        ,[Parameter(Mandatory)]$smtpPassword
    )

    try{

  
        $url = $secretServerRoot + "/webservices/sswebservice.asmx"

        $smtpPassSecure = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($smtpUserName,$smtpPassSecure)

        $secretServerUserNameParts = $secretServerUserName.Split("\")
        if ($secretServerUserNameParts.length -gt 1){
            $secretServerDomain = $secretServerUserNameParts[0]
            $secretServerUserName = $secretServerUserNameParts[1]
        }

        $proxy = New-WebServiceProxy -URI $url -UseDefaultCredential
        $authenticateResult = $proxy.Authenticate($secretServerUserName, $secretServerUserPassword, $null, $secretServerDomain)

        if ($authenticateResult.Errors.length -gt 0){
            Write-Host $authenticateResult.Errors[0]
            Write-Howt "Press Enter to Exit or Ctrl+c to Quit"
            Read-Host
            Exit
        }
        Write-Host "Successfully authenticated with Secret Server" 


        Import-CSV $userListPath -Header Username,EmailAddress | Foreach-Object{
   
            $searchUsersResult = $proxy.SearchUsers($authenticateResult.Token, $_.Username, $FALSE);
            if ($searchUsersResult.Errors.length -gt 0){
                Write-Host "Failed searching for user $($_.UserName). Skipping"
                Write-Host $searchUsersResult.Errors[0]
                Continue
            }
            if(-not $searchUsersResult.Users -or $searchUsersResult.Users.length -lt 1){
                Write-Host "Did not find user $($_.UserName). Creating."

                $t = $proxy.getType().namespace
                $currentUser = New-Object ($t + ".User")
                $currentUser.Username = $_.Username
                $currentUser.DisplayName = $_.Username
                $currentUser.EmailAddress = $_.EmailAddress
                $currentUser.Enabled = $TRUE
                $currentUser.Password = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..15] -join ''
    
                $addresult = $proxy.AddUser($authenticateResult.Token, $currentUser)

                Write-Host $addresult.Errors[0]
                Write-Host "Added " $_.EmailAddress 
            }
            else{
                Write-Host "Found user $($_.UserName). Updating password."
                $currentUser = $searchUsersResult.Users[0]
                $currentUser.Enabled = $TRUE
                $currentUser.Password = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..15] -join ''

                $addresult = $proxy.UpdateUser($authenticateResult.Token, $currentUser)
                
                Write-Host $addresult.Errors[0]
                Write-Host "Updated password for " $_.EmailAddress  
            }

            $searchUsersResult = $proxy.SearchUsers($authenticateResult.Token, $currentUser.Username, $FALSE);
            if ($searchUsersResult.Errors.length -gt 0){
                Write-Host "Cannot find user $($_.UserName). Skipping."
                Write-Host $searchUsersResult.Errors[0]
                Continue
            } 
    
            Write-Host "Found: $($searchUsersResult.Users.length) Users";
            Write-Host "First User: $($searchUsersResult.Users[0].Username)"    
    
            $getUserResult = $proxy.GetUser($authenticateResult.Token, $searchUsersResult.Users[0].Id);
            if ($getUserResult.Errors.length -gt 0){
                Write-Host "Cannot verify user $($_.UserName) by id $($searchUsersResult.Users[0].Id). Skipping"
                Write-Host $getUserResult.Errors[0]
                Continue
            }

            Write-Host "Sending email to $($currentUser.EmailAddress) for user $($currentUser.Username)"
            try {
                Send-Email -emailTo $currentUser.EmailAddress -username $currentUser.Username -password $currentUser.Password `
                       -smtpServer $smtpServer -smtpCredential $credential -secretServerUrl $secretServerRoot
                Write-Host "Email sent to $($currentUser.EmailAddress) for user $($currentUser.Username)"
    
            }
            catch{
                Write-Host "Error sending email to user $($currentUser.Username). Exception: $($_.Exception.Message)"
            }
        }
    }
    catch{
        Write-Host "Exiting due to unhandled Exception: $($_.Exception.Message)"
        Write-Host "Press Enter to Exit or Ctrl+c to Quit"
        Read-Host
        Exit
    }
}

function Send-Email{
    param(
        [Parameter(Mandatory)]$emailTo
        ,$emailFrom
        ,[Parameter(Mandatory)]$username
        ,[Parameter(Mandatory)]$password
        ,[Parameter(Mandatory)]$smtpServer
        ,$smtpPort = 25
        ,[Parameter(Mandatory)]$smtpCredential
        ,[Parameter(Mandatory)]$secretServerUrl
    )

    $emailFrom = ($emailFrom, "provisioning@$(([System.Uri]$secretServerUrl).Host -replace '^www\.').com" -ne $null)[0]
    $companyName = (Get-Culture).textinfo.totitlecase((([System.Uri]$secretServerUrl).Host -replace '^www\.|\.com$').ToLower())
    
    $body = @"
<html>
    <body><div>You have had an account created for you for this Thycotic Secret Server instance: $secretServerUrl</div>
    <h3>Please Note!</h3>
    <div>
        <strong>This login is sent in plain text; you will need to change your password on first login.</strong>
    </div>
    <br>
    <div>Username: $username</div>
    <div>Password: $password</div>
    <br>
    <span>For any issues, contact $emailFrom<br><br>Thanks!<br>$companyName Pam Team</span>
    </body>
</html>
"@

    Send-MailMessage -To $emailTo -From $emailFrom `
    -Subject "PAM Account Creation" -Credential $credential -SmtpServer $smtpServer `
    -BodyAsHtml $body -UseSsl -Port $smtpPort
}
export-modulemember -function Tss-Create-User-Email