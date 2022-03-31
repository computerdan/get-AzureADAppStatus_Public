#region Header
<#
DLC - 2022MAR31 -  Retrieve AzureAD App Current Status Information including Self-Consent Permissions and Users

get-AzureADAppStatus.ps1 in get-AzureADAppStatus.ps1 Repo

#>
#endregion

#region Globals
param(
    # IsThisDev
    [Parameter(Mandatory = $false)]
    [bool]
    $IsThisDev = $true,
    # IsThisLocal
    [Parameter(Mandatory = $false)]
    [bool]
    $isLocalrun = $true
)
#Dev
if ($isThisDev) {
    $EmailRecipients = "", "", ""
    $EmailTitle = "[[[DEV]]]"
}
#Live/Prod
if (!($IsThisDev)) {
    $EmailRecipients = "", ""
    $EmailTitle = "[[[LIVE]]]"
}

if ($isLocalrun) {
    set-location "C:\repos\get-AzureADAppStatus.ps1"
    $DateTimeStamp = get-date -f yyyy-MMM-dd_hhmmss
    $export_CSV = ((get-location).path) + "\AzureADAppStatus_$($DateTimeStamp).CSV"

    #Local - App and Email Creds
    $settings = get-content .\settings.json | ConvertFrom-Json
    
   

    #Local - Email
    $global:o365username = $settings.ExchangeOnlineSettings.ExchangeOnlineUser
    $o365pwd = convertto-securestring $settings.ExchangeOnlineSettings.ExchangeOnlinePassword -AsPlainText -Force
    $automationo365cred = new-object pscredential ($global:o365username, $o365pwd)

}

if (!($isLocalrun)) {
    #AzureAutomation - Email
    $DateTimeStamp = get-date -f yyyy-MMM-dd_hhmmss
    $export_CSV = "AzureADAppStatus_$($DateTimeStamp).CSV"
    
    #AzureAutomation - Send Email
    $global:automationo365cred = get-automationPSCredential -name "--*SomeAAStoredCred"
    $global:o365username = $automationo365cred.username
    $ExchangeOnlineSettings = @{
        "ExchangeOnlineUser"     = $global:automationo365cred
        "ExchangeOnlinePassword" = $global:automationo365cred.GetNetworkCredential().Password
    }

    #AzureAutomation - App
    $AADAppSettings = get-automationPSCredential -name "--*SomeAAStoredCred"
    $live = @{
        "ClientID"     = $AADAppSettings.username
        "RedirectURL"  = "urn:ietf:wg:oauth:2.0:oob"
        "ClientSecret" = $AADAppSettings.GetNetworkCredential().Password
    }
    $App = @{"live" = $live }
    #NotNeeded, but filled out anyway - just use $global:automationo365cred as cred itself


    $settings = @{
        "App"                    = $App
        "ExchangeOnlineSettings" = $ExchangeOnlineSettings
    }

}
#endregion

#region Functions
function Now () {
    #(get-date -f MM/dd/yyyy-hh:mm:ss)
    (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}
function get-PlainTextFromSecString {
    param(
        # SecurityStrong
        [Parameter(Mandatory = $true)]
        [securestring]
        $SecureString
    )

    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)            
    [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR) 
}
function get-accesstoken {
    [CmdletBinding()]
    param($TenantID, $ClientID, $redirectURL, $clientSecret)

    $getaccesstokenerr = $null

    try {
        $result = Invoke-RestMethod https://login.microsoftonline.com/$($TenantID)/oauth2/token `
            -Method Post -ContentType "application/x-www-form-urlencoded" `
            -Body @{client_id = $clientId; 
            client_secret     = $clientSecret; 
            redirect_uri      = $redirectURL; 
            grant_type        = "client_credentials";
            resource          = "https://graph.microsoft.com";
            state             = "32"
        } -ErrorVariable getaccesstokenerr
    
        # Send-SQLDiagNotification -message "AuthHeader Retrieved Successful"

        if ($null -ne $result) { return $result }
    }
    catch {
        # Send-SQLDiagNotification -message "Error Detected in get-accesstoken function"
        write-host -f Red "Could not retrieve Auth Token"
        # Exception is stored in the automatic variable _
        write-host -f Red $getaccesstokenerr
        $Global:Run = 1 #exit
        BREAK
    }
    
}
function get-authheader {

    #live - AzureAutomation

    $accesstoken = Get-AccessToken -TenantID $settings.app.live.TenantID -ClientID $settings.app.live.ClientID -redirectURL $settings.app.live.RedirectURL -clientSecret $settings.app.live.ClientSecret

    $token = $accesstoken.Access_Token
    $tokenexp = $accesstoken.expires_on

    if ($isLocalrun) {
        write-host -f black ""
        write-host -f Magenta "AuthToken Retrieved:"
        write-host -f Magenta "$token"
        write-host -f Magenta "Token Expiration Date:"
        write-host -f Magenta "$tokenexp"   
    }

    $global:authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer " + $token
        'ExpiresOn'     = $tokenexp
    }

    $TokenExpiratesOn = ConvertFromCtime -ctime $authHeader.ExpiresOn
    $NowUDate = (get-date).ToUniversalTime()

    $TokenTimeLeft = $TokenExpiratesOn - $NowUDate

    if ($isLocalrun) {
        write-host -f black ""
        write-host -f DarkMagenta "------------ Authentication Token ------------"
        Write-host -f Magenta "Token Generated.  Token Lifetime left: $($TokenTimeLeft)"
        write-host -f DarkMagenta "------------ Authentication Token ------------"
        write-host -f black ""
    }

}
function ConvertFromCtime ([Int]$ctime) {
    [datetime]$epoch = '1970-01-01 00:00:00'    
    [datetime]$result = $epoch.AddSeconds($Ctime)
    return $result
}
function Set-AuthRenewal {

    $TokenExpiratesOn = ConvertFromCtime -ctime $authHeader.ExpiresOn
    $NowUDate = (get-date).ToUniversalTime()

    $TokenTimeLeft = $TokenExpiratesOn - $NowUDate

    if ($TokenTimeLeft.TotalMinutes -lt 10 ) {
        get-authheader
        if ($isLocalrun) {
            Write-Warning "AuthHeader Renewal Triggered - Token TotalMinutes Time Left Was: $($TokenTimeLeft.TotalMinutes)"
        }
    }



}
function GAPI_Basic {

    $graphAPIError = $null

    # $URL = "https://graph.microsoft.com/beta/"
    $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $authHeader -ErrorVariable graphAPIError -ContentType "application/json"

    if ($graphAPIError) { return $graphAPIError }
    # else { return $invokeReturn }
    else { return $invokeReturn.value }

}
function GAPI_MultiPage {

    # $URL = "https://graph.microsoft.com/beta/"
    $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthHeader -ContentType "application/json" 
    $returnData += $invokeReturn.value
    if (!($invokeReturn.'@odata.nextLink')) { $returnData = $invokeReturn.value }
    if ($invokeReturn.'@odata.nextLink') {
        do {
            $invokeReturn = Invoke-RestMethod -Method Get -Uri $invokeReturn.'@odata.nextLink' -Headers $authHeader -ContentType "application/json" -ErrorAction SilentlyContinue
            $returnData += $invokeReturn.value
        }until (!($invokeReturn.'@odata.nextLink'))
    }

    return $returnData
}
function get-AllApplications {

    $URL = "https://graph.microsoft.com/beta/applications"
    # $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthHeader -ContentType "application/json" 
    $returnData += $invokeReturn.value
    if (!($invokeReturn.'@odata.nextLink')) { $returnData = $invokeReturn.value }
    if ($invokeReturn.'@odata.nextLink') {
        do {
            $invokeReturn = Invoke-RestMethod -Method Get -Uri $invokeReturn.'@odata.nextLink' -Headers $authHeader -ContentType "application/json" -ErrorAction SilentlyContinue
            $returnData += $invokeReturn.value
        }until (!($invokeReturn.'@odata.nextLink'))
    }

    return $returnData
}
function get-AllServicePrincipals {

    $URL = "https://graph.microsoft.com/beta/servicePrincipals"
    # $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthHeader -ContentType "application/json" 
    $returnData += $invokeReturn.value
    if (!($invokeReturn.'@odata.nextLink')) { $returnData = $invokeReturn.value }
    if ($invokeReturn.'@odata.nextLink') {
        do {
            $invokeReturn = Invoke-RestMethod -Method Get -Uri $invokeReturn.'@odata.nextLink' -Headers $authHeader -ContentType "application/json" -ErrorAction SilentlyContinue
            $returnData += $invokeReturn.value
        }until (!($invokeReturn.'@odata.nextLink'))
    }

    return $returnData
}
function get-oauth2PermissionsGrants {
    param(
        # AppID
        [Parameter(Mandatory = $true)]
        [string]
        $AppID
    )


    $URL = "https://graph.microsoft.com/beta/servicePrincipals/$($AppID)/oauth2PermissionGrants"
    
    # $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthHeader -ContentType "application/json" 
    $returnData += $invokeReturn.value
    if (!($invokeReturn.'@odata.nextLink')) { $returnData = $invokeReturn.value }
    if ($invokeReturn.'@odata.nextLink') {
        do {
            $invokeReturn = Invoke-RestMethod -Method Get -Uri $invokeReturn.'@odata.nextLink' -Headers $authHeader -ContentType "application/json" -ErrorAction SilentlyContinue
            $returnData += $invokeReturn.value
        }until (!($invokeReturn.'@odata.nextLink'))
    }

    return $returnData
}
function get-ServicePrincipalOwners {
    param(
        # ServicePrincipalID
        [Parameter(Mandatory = $true)]
        [string]
        $AppID
    )

    $selects = "accountEnabled,displayName,userPrincipalName,userType"

    $URL = "https://graph.microsoft.com/beta/servicePrincipals/$($AppID)/owners?`$select=$($selects)"
    
    # $URL = "https://graph.microsoft.com/v1.0/"
    
    $invokeReturn = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthHeader -ContentType "application/json" 
    $returnData += $invokeReturn.value
    if (!($invokeReturn.'@odata.nextLink')) { $returnData = $invokeReturn.value }
    if ($invokeReturn.'@odata.nextLink') {
        do {
            $invokeReturn = Invoke-RestMethod -Method Get -Uri $invokeReturn.'@odata.nextLink' -Headers $authHeader -ContentType "application/json" -ErrorAction SilentlyContinue
            $returnData += $invokeReturn.value
        }until (!($invokeReturn.'@odata.nextLink'))
    }

    return $returnData


}
#endregion

#region Process
get-authheader

if ($isLocalrun) {
    write-host "Retrieving All Service Principals"
}

$allServicePrincipals = get-AllServicePrincipals
$allServicePrincipalsCount = ($allServicePrincipals | measure).Count

if ($isLocalrun) {
    write-host "Found $($allServicePrincipalsCount) Service Principals"
}


$appCollection = @()

$processCount = 0
foreach ($sP in $allServicePrincipals) {
    $processCount++

    Set-AuthRenewal

    if ($isLocalrun) {
        write-host "Processing $($processCount) of $($allServicePrincipalsCount) - $($sp.displayName)"
    }

    $sPOwners = get-ServicePrincipalOwners -AppID $sP.id

    if (!($sPOwners)) {
        $AppOwnerUPNs = "NoAppOwnersFound"
    }
    if ($sPOwners) {
        $AppOwnerUPNs = $sPOwners | ConvertTo-Json

    }

    $oath2Perms = get-oauth2PermissionsGrants -AppID $sP.id

    if (!($sP.displayName)) { $appDisplayName = "" }
    if ($sP.displayName) { $appDisplayName = $sP.displayName }

    if (!($sp.AppHomePage)) { $appHomePage = "" }
    if ($sp.AppHomePage) { $appHomePage = $sP.AppHomePage }

    $appInfoHash = @{
        "Id"                                = $sp.id
        "App_ID"                            = $sp.appId
        "App_DisplayName"                   = $appDisplayName
        "App_OwnerOrganizationId"           = $sP.appOwnerOrganizationId
        "App_HomePage"                      = $appHomePage
        "App_isAuthorizationServiceEnabled" = $sP.isAuthorizationServiceEnabled
        "App_publisherName"                 = $sP.publisherName
        "App_replyUrls"                     = ($sp.replyUrls) | convertto-json
        "App_servicePrincipalNames"         = ($sP.servicePrincipalNames) | ConvertTo-Json
        "App_servicePrincipalType"          = $sp.servicePrincipalType
        "App_signInAudience"                = $sp.signInAudience
        "App_Tags"                          = ($sP.tags) | ConvertTo-Json
        "App_publishedPermissionScopes"     = ($sp.publishedPermissionScopes) | ConvertTo-Json
        "OwnersUPNs"                        = $AppOwnerUPNs
        "Oath2Perms"                        = $oath2Perms | select clientID, consentType, scope -Unique | ConvertTo-Json
    }

    $appinfoPSObject = new-object psobject -Property $appInfoHash

    $appCollection += $appinfoPSObject

}


#endregion

#region Export

$appCollection | export-csv -LiteralPath $export_CSV -NoTypeInformation -Delimiter ";"

#endregion

#region CleanUp
#endregion