### This code will retrieve a token for the account attemping to authenticate, pass the token to the header object, which will then be passed to the API call
$baseUrl = "https://<secret-server-url>"
#never store clear text passwords in scripts. 
$secureString = Read-Host -AsSecureString "Password"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
#The credentials need to be in a key value format, or what's known as a hash table. In production make sure you use
$creds = @{
    username = "<username>"
    password = $password
    grant_type = "password"
}
#clears the password value
$password=$null
# We then Post the credentials to the oauth2 endpoint, to get a token back. We can't use our token yet, we need to create a header object and pass the token
try
{
    $response = Invoke-RestMethod -Uri "$baseUrl/oauth2/token" -Method Post -Body $creds
    $headers = @{
        Authorization =  $($response.token_type +" "+ $response.access_token)
    }
    #clears the creds value
    $creds=$null
}
catch [System.Net.WebException]
{
    Write-Host "----- Exception -----"
    Write-Host  $_.Exception
    Write-Host  $_.Exception.Response.StatusCode
    Write-Host  $_.Exception.Response.StatusDescription
    $result = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($result)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd()
    throw $responseBody
}

# Check if we can authenticate. If this returns "True" then it means we were able to authenticate, and then expire the token
Invoke-RestMethod -Uri "$baseUrl/api/v1/oauth-expiration" -Method Post -Headers $headers -ContentType "application/json"