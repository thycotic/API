<#
.Synopsis
   Automate folder creation & permissions assignment for users with Domain Admin accounts
.DESCRIPTION
    The Script/Functions will pull users from a Secret Server group and creates folders for each user under a parent folder they can all see. The folders for these users will have permissions set to allow 
    that user access to the folder, and that user only. Like Secret Server's built in personal folders, except this structure supports Permissions inheritance, subfolder creation, and Secret Policy 
    assignments. This approach is intended for users with Domain Administrator Credentials, or other privileged credentials you'd like to store in the vault, and have some level of control over, yet giving users
    the flexibility to manage, add, and access their secrets
.EXAMPLE
   Token Authentication:
        New-SSFolderStructure -FolderName <sting> -GroupName <String> -Url <String "secret server base url"> -Permission <View, Edit, Owner> -SubFolders <String[]> -UseTokenAuthentication -UserName <String> -Password <String>
.EXAMPLE
   Integrated Windows Authentication:
        New-SSFolderStructure -FolderName <sting> -GroupName <String> -Url <String "secret server base url"> -Permission <View, Edit, Owner> -SubFolders <String[]> -UseDefaultCredentials
.PARAMETER FolderName
    The name of the parent folder for the subfolders we're creating.
.PARAMETER GroupName
    The name of the Secret Server group; Active Directory based, or Secret Server based. Please enter just the name of the group
.PARAMETER Url
    The base Url for Secret Server. https://mysecretserver.(com,local,gov,etc), https://mysecretserver, or https://mysecretserver/SecretServer (Or whatever the application name is if you renamed it in IIS)
.PARAMETER Permission
    Mandatory, Choose a permissions level for the users
.PARAMETER SubFolders
    Not mandatory. Creates a folder list under each user folder
.PARAMETER UserDefaultCredentials
    This switch parameter doens't need any parameter value. If used then the Script will use the current user credentials(the user running the script) to authenticate to Secret Server
.PARAMETER UseTokenAuthentication
    This switch parameter is used for username and password authentication to Secret Server in order to generate a token. That token will be used in subsequent API calls. This is a less secure approach, but usefull for a quick test
.PARAMETER UserName
    Only used if UseTokenAuthentication is called
.PARAMETER Password
    Only used if UseTokenAuthentication is called
    
.OUTPUTS
   None
#>

Function New-SSFolderStructure {
    [CmdletBinding()]
    Param(
        [parameter(mandatory=$true,Position=0)]
        [ValidateNotNullOrEmpty()]
        [String]
        $FolderName,
        [parameter(mandatory=$true,Position=1,HelpMessage="Enter the group from Secret Server.Name only")]
        [ValidateNotNullOrEmpty()]
        [String]
        $GroupName,
        [parameter(Mandatory=$true,position=2)]
        [ValidateSet("Owner","Edit","View")]
        [String]
        $Permission,
        [parameter(Mandatory=$true,position=3)]
        [ValidateScript(
        {
            If($_ -match "^((http|https)://)?([\w+?\.\w+])+([a-zA-Z0-9\~\!\@\#\$\%\^\&\*\(\)_\-\=\+\\\/\?\.\:\;\'\,]*)?$") {
                $true
            }
            else{
                Throw "$_ is not a valid URL format. Please enter url format as https://hostname, https://hostname/application"
            }
        })
        ]
        [String]
        $Url,
        [parameter(Mandatory=$false,HelpMessage="This optional parameter creates folders under each user's folder. Enter folder names separated by commas")]
        [String[]]
        $SubFolders,
        [parameter(ParameterSetName="WindowsAuthentication",Mandatory=$true)]
        [Switch]
        $UseDefaultCredentials,
        [parameter(ParameterSetName="TokenAuthentication",Mandatory=$true)]
        [Switch]
        $UseTokenAuthentication,
        [parameter(Mandatory=$true,ParameterSetName="UserName",Position=5)]
        [parameter(ParameterSetName="TokenAuthentication")]
        [String]
        $UserName,
        [parameter(Mandatory=$true,ParameterSetName="Password",Position=6)]
        [parameter(ParameterSetName="TokenAuthentication")]
        [String]
        $Password

    )
    begin {
        # Error Function
        function Write-WebError([string]$Prefix) {    
            Write-Host "----- Exception -----"
            Write-Host  $_.Exception
            Write-Host  $_.Exception.Response.StatusCode
            Write-Host  $_.Exception.Response.StatusDescription
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd()
            throw $Prefix + $responseBody
        }
        #region Authentication
            ##########################################################
            #Logic to use token AUTH vs integrated windows credentials
            ##########################################################
        if($UseTokenAuthentication) {
            $creds=@{
                username=$UserName
                password=$Password
                grant_type="password"
            }
            $authUrl=$Url+"/oauth2/token"
            $api=$Url+"/api/v1"
            try {
                $authenticate=Invoke-RestMethod -Uri $authUrl -Method Post -Body $creds
            }
            catch {
                Write-WebError -Prefix "Authentication Error"
            }
            $token=$authenticate.access_token
            $headers=New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "Bearer $token")
            $params=@{
                Headers=$headers
                ContentType="Application/Json"
            }
        }
        else {
            $params=@{
                UseDefaultCredentials=$true
                ContentType="Application/Json"
            }
            $api=$Url+"/winauthwebservices/api/v1"
        }
        #endregion
        ##################################################################################
        #This child function will get exact Group Name/Folder Name in case of similarities
        ##################################################################################
        Function Get-UniqueRecords {
            [CmdletBinding()]
            Param(
                [Parameter(mandatory=$true)]
                [String]
                $UniqueName,
                [Parameter(mandatory=$true)]
                [ValidateSet("groups","folders")]
                [String]
                $Type
            )
            try {
                $Records=Invoke-RestMethod -Uri ($api+"/$Type/?filter.searchText=$UniqueName") -Method Get @params
            }
            catch {
                Write-WebError -Prefix "Error getting $Type"
            }
            if($Type -eq "folders") {
                $property="folderName"   
            }
            else {
                $property="name"
            }
            $object=New-Object PSObject
            $object | Add-Member -MemberType NoteProperty -Name Name -Value $null
            $object | Add-Member -MemberType NoteProperty -Name Id -Value $null
            $object | Add-Member -MemberType NoteProperty -Name Exists -Value $null
            if($Records.records.Count -ge 1) {
                foreach($record in $Records.records) {
                    if($record.$property -eq $UniqueName) {
                        $object.Name=$record.$property
                        $object.Id=$record.id
                        $object.Exists=$true
                        return $object
                    }
                    else {
                        $object.Exists=$false
                        return $object
                    }
                }
            }
            else {
                $object.Exists=$false
                return $object
            }
        }# End unique records function
    }#End Begin block
    process {
        #region Users
            ############################################################################################################
            #Get the group, and then get the user Ids from the group. We will then query against the users’ API endpoint
            #with our new IDs to extract the Display Name, which will be our child folder names
            ############################################################################################################
        $group=Get-UniqueRecords -UniqueName $GroupName -Type groups
        $groupId=$group.id
        try {
            $groupUsers=Invoke-RestMethod -Uri ($api+"/groups/$groupId/users") -Method Get @params
        }
        catch {
            Write-WebError -Prefix "Error getting group users"
        }
        $UserIds=$groupUsers.records.userId
        $userNames=@{}
        ###########################################################################################################################################################################
        #Here we put the display names and the users in a hash table that we can use later for folder creation. This step is cleaner than have multiple arrays for username and IDs
        ###########################################################################################################################################################################
        foreach($id in $UserIds) {
            $user=Invoke-RestMethod -Uri ($api+"/users/$id") -Method Get @params
            $userNames.add($user.displayName,$user.id)
        }
        #endregion

        #region Folders
            ##############################################################################################
            #if parent exists, we get the child folders and store then in an array called childfoldernames
            ##############################################################################################
        $parentFolder=Get-UniqueRecords -UniqueName $FolderName -Type folders
        if($parentFolder.Exists) {
            $parentFolderId=$parentFolder.id
            try {
                $childFolders=Invoke-RestMethod -Uri ($api+"/folders/$parentFolderId/?args.getAllChildren=true") -Method Get @params
                if($childFolders.childFolders.Count -gt 0) {
                    $childExits=$true
                    $childFolderNames=$childFolders.childFolders.folderName
                }
            }
            catch {
                Write-WebError -Prefix "Error getting child folders"
            }
        }
        ##################################################################################################################################
        #If it doesn't exists. Get an empty folder object, and use this as a reference to create the parent folder, and the children later
        ##################################################################################################################################
        elseif($parentFolder.Exists -eq $false) {
            try {
                $stubFolder=Invoke-RestMethod -Uri ($api+"/folders/stub") -Method Get @params
                $stubFolder.folderName=$FolderName
                $data = $stubFolder | ConvertTo-Json
                $folderCreate=Invoke-RestMethod -Uri ($api+"/folders") -Method Post @params -Body $data
                $parentFolderId=$folderCreate.id
                $parentFolderPermissionData=@{
                    folderId=$parentFolderId
                    groupId=$groupId
                    folderAccessRoleName="View"
                    secretAccessRoleName="List"
                } | ConvertTo-Json
                Invoke-RestMethod -Uri ($api+"/folder-permissions") -Method Post -Body $parentFolderPermissionData @params | Out-Null
            }
            catch {
                Write-WebError -Prefix "Error creating parent folder $FolderName"
            }
            Start-Sleep 1
        }
        #Begin Subfolders
            #########################################################################################################################################################
            #If child folders exist, we then loop through them against our users hash table. If the user matches a folder name, then it's removed from the hash table
            #to prevent errors
            #########################################################################################################################################################
        if($childExits) {
            for($i=0; $i -le $childFolderNames.Count; $i++) {
                foreach($user in ($userNames.Clone()).Keys) {
                    if($user -eq $childFolderNames[$i]) {
                        $userNames.Remove($user)
                    }
                }
            }
        }
        ################################################################################################################################################
        #Here we begin creating the child folders and assigning permissions to them. Set them to not inherit permissions from parent, and inherit policy
        ################################################################################################################################################
        $stubFolder=Invoke-RestMethod -Uri ($api+"/folders/stub") -Method Get @params
        $stubFolder.inheritSecretPolicy=$true
        foreach($user in $userNames.GetEnumerator()) {
            $stubFolder.folderName=$user.Name
            $stubFolder.parentFolderId=$parentFolderId
            $stubFolder.inheritPermissions=$false
            $childFolderData = $stubFolder | ConvertTo-Json
            try {
                $folderCreate=Invoke-RestMethod -Uri ($api+"/folders") -Method Post -Body $childFolderData @params
                #If subfolders are defind then the script will create these subfolders for each user
                if($SubFolders -ne $null) {
                    foreach($subfolder in $SubFolders) {
                        $stubFolder.folderName=$subfolder
                        $stubFolder.parentFolderId=$folderCreate.id
                        $stubFolder.inheritPermissions=$true
                        $childFolderData=$stubFolder | ConvertTo-Json
                        Invoke-RestMethod -Uri ($api+"/folders") -Method Post -Body $childFolderData @params |Out-Null
                    }
                }
            }
            catch {
                Write-WebError -Prefix "Error creating sub folder $FolderName"
            }
            $folderId=$folderCreate.id
            ###########################################################################################################################################################################
            #we need to remove the group permissions from the child folders, since only the end user and the Admin should have access. This can be modified to remove the admin as well
            ###########################################################################################################################################################################
            try {
                $folderpermissions=Invoke-RestMethod -Uri ($api+"/folder-permissions/?filter.folderId=$folderId") -Method Get @params
                foreach($folderpermission in $folderpermissions.records) {
                    if($folderpermission.groupId -eq $groupId) {
                        $permissionId = $folderpermission.id
                        Invoke-RestMethod -Uri ($api+"/folder-permissions/$permissionId") -Method Delete @params | Out-Null
                    }
                }
            }
            catch {
                Write-WebError -Prefix "Error deleting permissions on folder ID $folderId"
            }                    
            Start-Sleep -Milliseconds 500
            ###################
            #adding permissions
            ###################
            $userId=$user.Value
            $permissionData=@{
                folderId=$folderId
                userId=$userId
                folderAccessRoleName=$Permission
                secretAccessRoleName=$Permission
            } | ConvertTo-Json
            try {
                Invoke-RestMethod -Uri ($api+"/folder-permissions") -Method Post -Body $permissionData @params | Out-Null
            }
            catch {
                Write-WebError -Prefix "Error adding permissions on sub folder ID $folderId"
            }
        }
        #endregion
    }#end process block
}