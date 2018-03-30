# Purpose
This Script is meant to create folders which replicate our personal folders, but with additional capabilities for centralized management through Secret policy, Template Restrictions, etc. A common use case for this example is for personal elevated accounts for various systems.

Synopsis
--------
Automate folder creation & permissions assignment for users with Domain Admin accounts, or similar elevated user accounts

DESCRIPTION
------------
The Script/Functions will pull users from a Secret Server group and create folders for each user under a parent folder they can all see. The sub-folders for each user will have permissions set to allow that user access to the folder, and that user only. Like Secret Server's built in personal folders, except this structure supports permission inheritance, subfolder creation, and Secret Policy assignments. This approach is intended for users with Domain Administrator Credentials, or other privileged credentials you'd like to store in the vault, and have some level of control over, yet giving users the flexibility to manage, add, and access their secrets

Examples
--------
- Token Authentication:
    ```powershell
    - New-SSFolderStructure -FolderName <sting> -GroupName <String> -Permissions <View, Edit, Owner> -Url <String "secret server base url"> 
     -SubFolders <String[]> -UseTokenAuthentication -UserName <String> -Password <String>
    ````
 - Integrated Windows Authentication:
    ```powershell    
    New-SSFolderStructure -FolderName <sting> -GroupName <String> -Permissions <View, Edit, Owner> -Url <String "secret server base url"> 
     -SubFolders <String[]> -UseDefaultCredentials
    ```
## .PARAMETER FolderName
    The name of the parent folder for the subfolders we're creating.
## .PARAMETER GroupName
    The name of the Secret Server group; Active Directory based, or Secret Server based. Please enter just the name of the group
## .PARAMETER Permissions
    Mandatory, Choose a permissions level for the users
## .PARAMETER Url
    The base Url for Secret Server. https://mysecretserver.(com,local,gov,etc), https://mysecretserver, or https://mysecretserver/SecretServer (Or whatever the application name is if you renamed it in IIS)
## .PARAMETER AdminGroupName
    Not mandatory. The name of the Secret Server Administrative group to Add Secrets to new Enhanced Personal Folders; Active Directory based, or Secret Server based. Please enter just the name of the group
## .PARAMETER AdminPermissions
    Not mandatory. Currently the only accepted value is the Permissions pair "AddSecret\List" which allows admin group to add secrets and acknowledge that they exist.
## .PARAMETER SubFolders
    Optional. Creates a folder list under each user folder
## .PARAMETER UserDefaultCredentials
    This switch parameter doens't need any parameter value. If used then the Script will use the current user credentials(the user running the script) to authenticate to Secret Server
## .PARAMETER UseTokenAuthentication
    This switch parameter is used for username and password authentication to Secret Server in order to generate a token. That token will be used in subsequent API calls. This is a less secure approach, but usefull for a quick test
## .PARAMETER UserName
    Only used if UseTokenAuthentication is called
## .PARAMETER Password
    Only used if UseTokenAuthentication is called
