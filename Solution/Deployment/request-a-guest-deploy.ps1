## Request-a-Guest App Deployment
<#
.SYNOPSIS
    Deploys required assets of the "Request-a-Guest" solution.

.DESCRIPTION
    Deploys the "Request-a-Guest" solution solution (excluding the PowerApp).

.PARAMETER AdminUsername
    UserPrincipalName (UPN) of the Azure / Office 365 Admin Account.

.PARAMETER Mfa
    Defines is Multi-Factor Authentication is required.

.EXAMPLE
    request-a-guest-deploy.ps1 -AdminUsername <Office 365 Administrator Account> -Mfa <$false/ $true>

-----------------------------------------------------------------------------------------------------------------------------------

Authors : Tobias Heim (Sr. CSA-E - Microsoft)
Version : 1.2

-----------------------------------------------------------------------------------------------------------------------------------

DISCLAIMER:
   THIS CODE IS SAMPLE CODE. THESE SAMPLES ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND.
   MICROSOFT FURTHER DISCLAIMS ALL IMPLIED WARRANTIES INCLUDING WITHOUT LIMITATION ANY IMPLIED WARRANTIES
   OF MERCHANTABILITY OR OF FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK ARISING OUT OF THE USE OR
   PERFORMANCE OF THE SAMPLES REMAINS WITH YOU. IN NO EVENT SHALL MICROSOFT OR ITS SUPPLIERS BE LIABLE FOR
   ANY DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR LOSS OF BUSINESS PROFITS, BUSINESS
   INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR OTHER PECUNIARY LOSS) ARISING OUT OF THE USE OF OR
   INABILITY TO USE THE SAMPLES, EVEN IF MICROSOFT HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
   BECAUSE SOME STATES DO NOT ALLOW THE EXCLUSION OR LIMITATION OF LIABILITY FOR CONSEQUENTIAL OR
   INCIDENTAL DAMAGES, THE ABOVE LIMITATION MAY NOT APPLY TO YOU.
#>

Param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)][String]$AdminUsername,
    [Parameter(Mandatory = $true)][bool]$Mfa
)

#region Credentials and Pwds

# Credential Object for Non-Mfa scenario
if (!$Mfa) {
    Write-Host "NOTE" -ForegroundColor Yellow -NoNewline
    Write-Host ": In a later stage of the deployment you will be prompted to enter the Admin Credentials again to connect to SharePoint (PnP)."
    $Adminpwd = Read-Host "Now please enter the Password of the O365 and Azure Administrator" -AsSecureString
    [PSCredential]$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList($AdminUsername, $Adminpwd) 
}

# Password of the Service Account
$ServiceAccountPwd = Read-Host 'Enter Password of the Service Account "ServiceAccountUPN" you defined in the configfile' -AsSecureString

#endregion
#region global functions

# Function to check if required config files exist
function checkIfFileExists ($file) {
    if (!(Test-Path $file)) {
        throw('Please make sure that the following file exists: {0}' -f $file)
    }
}

# Function to install required PowerShell Modules 
function installModules ($modules) {
    if ((Get-PSRepository).InstallationPolicy -eq "Untrusted") {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        $psTrustDisabled = $true
    }

    foreach ($module in $modules) {
        $instModule = Get-InstalledModule -Name $module -ErrorAction:SilentlyContinue
        if (!$instModule) {
            if ($module -eq "PnP.PowerShell") {
                $spModule = Get-InstalledModule -Name "SharePointPnPPowerShellOnline" -ErrorAction:SilentlyContinue
                if ($spModule) {
                    throw('Please remove the "SharePointPnPPowerShellOnline" before the deployment can install the new module "PnP.PowerShell"')                    
                }
                try {
                    Write-Host('Install PowerShell Module {0}' -f $module)
                    Install-Module -Name $module -Scope CurrentUser -AllowClobber -Confirm:$false -MaximumVersion 1.9.0
                } catch {
                    throw('Failed to install PowerShell module {0}: {1}' -f $module, $_.Exception.Message)
                } 
            } else {
                try {
                    Write-Host('Install PowerShell Module {0}' -f $module)
                    Install-Module -Name $module -Scope CurrentUser -AllowClobber -Confirm:$false
                } catch {
                    throw('Failed to install PowerShell module {0}: {1}' -f $module, $_.Exception.Message)
                } 
            }
        }
    }

    if ($psTrustDisabled) {
        Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted
    }
}

# Check that the provided location is a valid Azure location
function validateAzureLocation {
    param (
        [String]$Location
    )
    $AzureLocations = (Get-AzLocation).Location
    if (!($AzureLocations | Where-Object {$_ -eq $Location})) {
        throw('Please provide a valid location (https://azure.microsoft.com/en-gb/global-infrastructure/locations/): {0}' -f $Location)
    }
}

# Check if resource names are available
function checkResourceName {
    param (
        [String]$ResourceGroupName,
        [String]$AppRegistrationName,
        [String]$keyVaultName,
        [String]$AutomationAccountName
    )

    # Check if resource group name is available
    Write-Host('Check if Azure resource "{0}" already exists or name is already taken...' -f $ResourceGroupName)
    if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction:SilentlyContinue) {
        throw('Azure resource group with the same name already exists: {0}' -f $ResourceGroupName)
    }

    # Check if Azure app registration name is available
    Write-Host('Check if Azure app registration "{0}" already exists or name is already taken...' -f $AppRegistrationName)
    if (Get-AzADApplication -DisplayName $AppRegistrationName -ErrorAction:SilentlyContinue) {
        throw('Azure app registration with the same name already exists: {0}' -f $AppRegistrationName)
    }

    # Check if all other azures resource names are available
    [Array]$otherResources = $keyVaultName,$AutomationAccountName,"DomainCheck","RequestAGuest","requestaguest-azuread","requestaguest-azureautomation","requestaguest-keyvault","requestaguest-office365","requestaguest-office365","requestaguest-sharepointonline"
    foreach ($otherResource in $otherResources) {
        Write-Host('Check if Azure resource "{0}" already exists or name is already taken...' -f $otherResource)
        if (Get-AzResource -Name [String]$otherResource -ResourceGroupName [String]$ResourceGroupName -ErrorAction:SilentlyContinue) {
            throw('Azure resource with the same name already exists: {0}' -f $otherResource)
        }
    }
}

# Function to configure SharePoint site and import list template
function configureSharePointSite {
    param (
        [string]$ServiceAccountUPN,
        [string]$spListTemplate,
        [string]$ApproverGroup,
        [string]$RequesterGroup
    )

    # Apply SharePoint list template
    try {
        Write-Host("Applying provisioning template...")
        Invoke-PnPSiteTemplate -Path $spListTemplate -Handlers Lists -ClearNavigation -ErrorAction:Stop
    } catch {
        throw('Error occured while applying SharePoint list template: {0}' -f $_.Exception.Message)
    }

    # Get owners & requester group
    $spGroup = Get-PnPGroup | Where-Object Title -Match "Owners"
    $spGroupRequester = Get-PnPGroup | Where-Object Title -Match "Members"

    if ($spGroup.Users |Where-Object {$_.Email -ne $ServiceAccountUPN}) {
        # Add service account to owners group
        try {
            Write-Host('Adding Service Account "{0}" to Owners group' -f $ServiceAccountUPN)
            Add-PnPGroupMember -LoginName $ServiceAccountUPN -Group $spGroup -ErrorAction:Stop
        } catch {
            throw('Error occured while adding the user to SharePoint site as Owner: {0}' -f $_.Exception.Message)
        }
    } else {
        Write-Host('Service account {0} is already "owner" of the the SharePoint site.' -f $ServiceAccountUPN)
    }

    # Add the approver group to owners group
    try {
        Write-Host('Adding Group "{0}" to owners group' -f $ApproverGroup)
        Add-PnPGroupMember -LoginName $ApproverGroup -Group $spGroup -ErrorAction:Stop
    } catch {
        throw('Error occured while adding the "{0}" to SharePoint site owners group: {1}' -f $ApproverGroup, $_.Exception.Message)
    }

    # Add the requester group to owners group
    try {
        Write-Host('Adding Group "{0}" to members group' -f $RequesterGroup)
        Add-PnPGroupMember -LoginName $RequesterGroup -Group $spGroupRequester -ErrorAction:Stop
    } catch {
        throw('Error occured while adding the "{0}" to SharePoint site owners group: {1}' -f $RequesterGroup, $_.Exception.Message)
    } 

}

# Function to create SharePoint Site
function createRequestsSharePointSite {
    param(
        [string]$spSiteUrl,
        [string]$spSiteName,
        [string]$spSiteAlias,
        [string]$spSiteDesc,
        [string]$saUPN,
        [string]$listTemplate,
        [string]$ApproverGroup,
        [string]$RequesterGroup
    )
        if (!(Get-PnPTenantSite -Url $spSiteUrl -ErrorAction:SilentlyContinue)) {
            # Site will be created with current user connected to PnP as the owner/primary admin
            try {
                Write-Host('Creating Guest Requests SharePoint site: {0}' -f $spSiteName)
                New-PnPSite -Type TeamSite -Title $spSiteName -Alias $spSiteAlias -Description $spSiteDesc -ErrorAction:Stop
                Write-Host('Site "{0}" Site was successful created' -f $spSiteName)
                
                # Configure SharePoint Site
                Write-Host('Wait until SharePoint site is ready...')
                Start-Sleep -s 60
                
                Write-Host('Connect to SharePoint Site: {0}' -f $spSiteUrl)
                try {
                    Connect-PnPOnline $spSiteUrl -Interactive -ErrorAction:Stop
                } catch {
                    throw('Failed to connect to SharePoint site {0}: {1}' -f $spSiteUrl, $_.Exception.Message)
                }
                
                Write-Host('Configure SharePoint Site: {0}' -f $spSiteUrl)
                $spConfigParams = @{
                    ServiceAccountUPN = $saUPN
                    spListTemplate = $listTemplate
                    ApproverGroup = $ApproverGroup
                    RequesterGroup = $RequesterGroup
                }
                configureSharePointSite @spConfigParams
            } catch {
                throw('Error occured while creating of the SharePoint site: {0} - {1}' -f $spSiteName, $_.Exception.Message)
            }
        } 
        else {
            return('A SharePoint Site with the same name already exists: {0}' -f $spSiteName)
        }        
}

# Function to create Azure resource group 
function createResourceGroup {
    param (
        [string]$AzureRgName,
        [string]$AzureLocation
    )
    if (Get-AzResourceGroup -Name $AzureRgName -ErrorAction:SilentlyContinue) {
        Write-Host('Azure resource group already exist {0}' -f $AzureRgName)
    }
    else {
        try {
            Write-Host('Creating Azure resource group {0}' -f $AzureRgName)
            New-AzResourceGroup -Name $AzureRgName -Location $AzureLocation -ErrorAction:Stop
            Write-Host('Successfully created resource group {0}' -f $AzureRgName)
        }
        catch {
            throw('Failed to create Azure resource group {0}: {1}' -f $AzureRgName, $_.Exception.Message)
        }
    }
}

# Function to check Azure app regirstration
function getAzureADApp {
    param (
        [String]$Name
    )
    $app = az ad app list --filter "displayName eq '$Name'" | ConvertFrom-Json
    return $app
}

# Function to create or update the required Azure app registration
function createAzureADApp {
    param (
        [String]$appName,
        [string]$manifestPath
    )
    # Check if the app already exists
    $app = GetAzureADApp -Name $appName
    
    if ($app) {
        # Update Azure ad app registration using Azure CLI
        Write-Host('Azure AD App Registration {0} already exists - updating existing app...' -f $appName)
        az ad app update --id $app.appId --required-resource-accesses $manifestPath |Out-Null
        if (!$?) {
            throw('Failed to update AD App {0}' -f $appName)
        }
        Write-Host "Waiting for App Registration to finish updating..."
        Start-Sleep -s 60
        Write-Host('Updated Azure AD App Registration: {0}' -f $AppName)
    } 
    else {
        # Create Azure ad app registration using Azure CLI
        Write-Host('Creating Azure AD App Registration: {0}...' -f $appName)
        az ad app create --display-name $appName --required-resource-accesses $manifestPath |Out-Null
        if (!$?) {
            throw('Failed to create AD App Registration {0}' -f $appName)
        }
        Write-Host('Waiting for App Registration {0} to finish creating...' -f $appName)
        Start-Sleep -s 60
        Write-Host('Successfully created Azure AD App Registration: {0}...' -f $appName)

        # Get the app registration details
        $app = GetAzureADApp -Name $appName
    }

    # (OPTIONAL) End-date for the secret is set to 365 days from now
    #$endDate = (Get-Date).AddDays(90).ToString("yyyy-MM-dd")

    # Set the app registration secret
    Write-Host('Setting Azure AD App Registration Secret: {0}...' -f $appName)
    $appSec = az ad app credential reset --id $app.appId # --end-date $endDate
    if (!$?) {
        throw('Failed to set Azure AD App Registration Secret: {0}' -f $appName)
    }
    # Get app registration secret
    $appDetails = $appSec |ConvertFrom-Json
    $appSecValue = ($appDetails).password

    # Grant admin consent for app registration required permissions using Azure CLI
    Write-Host('Granting admin content to App Registration: {0}' -f $appName)
    az ad app permission admin-consent --id $app.appId |Out-Null
    if (!$?) {
        throw('Failed to grant admin content to App Registration: {0}' -f $appName)
    }
    Write-Host "Waiting for admin consent to complete..."
    Start-Sleep -s 60
    Write-Host('Granted admin consent to App Regiration: {0}' -f $AppName)

    return $appSecValue
}

# Function to create Azure Key Vault
function createConfigureKeyVault {
    param (
        [String]$KeyVaultName,
        [String]$ResourceGroupName,
        [String]$Location,
        [String]$appName,
        [String]$appSecret
    )
    Write-Host "Creating/Updating Key Vault and setting secrets..."
    # Check if the key vault already exists
    $keyVault = Get-AzKeyVault -Name $KeyVaultName
    if(!$keyVault) {
        # Use the tenant name in the key vault name to ensure it is unique - first 8 characters only due to maximum allowed length of key vault names
        try {
            New-AzKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction:Stop
            $appServicePrincipalId = Get-AzADServicePrincipal -DisplayName $AppRegistrationName | Select-Object -ExpandProperty Id
            $appId = (GetAzureADApp -Name $AppRegistrationName).appId
            # Create/update the secrets for the ad app id and password
            try {
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'GuestAppID' -SecretValue (ConvertTo-SecureString -String $appId -AsPlainText -Force) | Out-Null
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name 'GuestAppSecret' -SecretValue (ConvertTo-SecureString -String $appSecret -AsPlainText -Force) | Out-Null
                Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ObjectId $appServicePrincipalId -PermissionsToSecrets List,Get
                Write-Host('Finished creating/updating Key Vault {0}' -f $KeyVaultName)
            } catch {
                throw('Failed to update Azure Vault: {0}' -f $_.Exception.Message)
            }
        } catch {
            throw('Failed to create Azure Key Vault {0}: {1}' -f $KeyVaultName, $_.Exception.Message)
        }
    }
}

# Function to create Azure Automation Account to home PS Runbook
function createAutomationAccount {
    param (
        [string]$ResourceGroup,
        [string]$AutomationAccount,
        [string]$DomainCheckScript,
        [string]$Location,
        [string]$ServiceAccountUPN,
        [Security.SecureString]$ServiceAccountPwd
    )
    if (!(Get-AzAutomationAccount -ResourceGroupName $ResourceGroup -Name $AutomationAccount -ErrorAction:SilentlyContinue)){
        # Create Azure Automation Account
        try {
            Write-Host('Creating Azure Automation Account {0}' -f $AutomationAccount)
            New-AzAutomationAccount -Name $AutomationAccount -Location $Location -ResourceGroupName $ResourceGroup -ErrorAction:Stop
        } catch {
            throw('Failed to create Automation Account {0}: {1}' -f $AutomationAccount, $_.Exception.Message)
        }
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $ServiceAccountUPN, $ServiceAccountPwd
        
        # Add credentials to Automation Account
        try {
            Write-Host('Creating Azure Automation Account Credentials "ragGuest"')
            New-AzAutomationCredential -AutomationAccountName $AutomationAccount -Name "ragGuest" -Value $Credential -ResourceGroupName $ResourceGroup -ErrorAction:Stop
        } catch {
            throw('Failed to create Automation Account credentials "ragGuest"' -f $_.Exception.Message)
        }

        # Add required Azure AD Preview module to Automation Account
        try {
            Write-Host('Install PowerShell module "AzureADPreview" in automation account {0}' -f $AutomationAccount)
            $moduleParams = @{
                AutomationAccountName = $AutomationAccount
                ResourceGroupName = $ResourceGroup
                Name = "AzureADPreview"
                ContentLinkUri = "https://www.powershellgallery.com/api/v2/package/AzureADPreview/2.0.2.129"
            }
            New-AzAutomationModule @moduleParams -ErrorAction:Stop
        } catch {
            throw('Failed to install AzureADPreview module in automation account' -f $_.Exception.Message)
        }

        # Publish PS runbook to Azure Automation Account
        try {
            Write-Host('Creating Azure Automation Account Credentials "requestaguest"')
            New-AzAutomationRunbook -AutomationAccountName $AutomationAccount -Name 'requestaguest' -ResourceGroupName $ResourceGroup -Type PowerShell
            Write-Host('Publish Script to Azure Runbook - Please wait...')
            Start-Sleep 30
            $script = Get-ChildItem -Path $DomainCheckScript
            $RunbookInfo = @{
                Name = $script.BaseName
                Path = $script.Fullname
                Force = $true
                Published = $true
                Type = "PowerShell"
                ResourceGroupName = $ResourceGroup
                AutomationAccountName = $AutomationAccount
            }
            Import-AzAutomationRunbook @RunbookInfo
        } catch {
            throw('Failed to create Automation Automation Runbook {0}' -f $AutomationAccount, $_.Exception.Message)
        }
    }
}

# Add Service account to Key Vault
function grantAzureKvPermissionToServiceAcount {
    param (
        [String]$subscriptionId,
        [String]$ServiceAccountUPN,
        [String]$Scope,
        [String]$Resource,
        [String]$ResourceGroupName
    )
    $roleParams = @{
        SignInName = $ServiceAccountUPN
        RoleDefinitionName = "Owner"
        Scope = "/subscriptions/" + $subscriptionId + "/resourceGroups/" + $ResourceGroupName + $Scope + $Resource
    }
    try {
        New-AzRoleAssignment @roleParams
    } catch {
        throw('Failed to add Service Account {0} to Azure Ressource {1}: {2}' -f $ServiceAccountUPN, $Resource, $_.Exception.Message)
    }
}

# Add Service account to automation account
function grantAzureAaPermissionToServiceAcount {
    param (
        [String]$subscriptionId,
        [String]$ServiceAccountUPN,
        [String]$Scope,
        [String]$Resource,
        [String]$ResourceGroupName
    )
    $roleParams = @{
        SignInName = $ServiceAccountUPN
        RoleDefinitionName = "Owner"
        Scope = "/subscriptions/" + $subscriptionId + "/resourceGroups/" + $ResourceGroupName + $Scope + $Resource #+ "/runbooks/runbook_domain-check"
    }
    try {
        New-AzRoleAssignment @roleParams
    } catch {
        throw('Failed to add Service Account {0} to Azure Ressource {1}: {2}' -f $ServiceAccountUPN, $Resource, $_.Exception.Message)
    }
}

# Function to create Approver Security Group
function createGroup {
    param (
        [String]$GroupName
    )
    if (!(Get-AzureADGroup -Filter "DisplayName eq '$GroupName'" -ErrorAction:SilentlyContinue)) {
        $Description = "Request-a-Guest App Group"
        try {
            New-AzureADGroup -Description $Description -DisplayName $GroupName -MailEnabled $false -SecurityEnabled $true -MailNickName $GroupName -ErrorAction:Stop
        }
        catch {
            throw('Failed to create Security Group {0}: {1}' -f $GroupName, $_.Exception.Message)
        }
    } else {
        Write-Host('Group already exists: {0}' -f $GroupName)
    }
}

# Function to get the Approver Security Group
function getGroup {
    param (
        [String]$GroupName
    )
    try {
        $Group = Get-AzureADGroup -Filter "DisplayName eq '$GroupName'"
        Return $Group.ObjectId
    }
    catch {
        throw('Failed to get Security Group {0}: {1}' -f $GroupName, $_.Exception.Message)
    }
}

# Function add Service Account to Approver Security Group
function addSaToApproverGroup {
    param (
        [String]$GroupName,
        [String]$saUPN
    )
    # Get approver group object ID
    $GroupObjId = getGroup -GroupName $GroupName
    # Get service account object ID
    $SaObjId = (Get-AzureADUser -Filter "UserPrincipalName eq '$saUPN'").ObjectId
    # Check if is service account is already member of the group
    if (!(Get-AzureADGroupMember -ObjectId $GroupObjId |Where-Object {$_.ObjectId -eq $SaObjId})) {
        try {
            Write-Host('Add ServiceAccount {0} to Approver Group {1}' -f $saUPN, $GroupName)
            Add-AzureADGroupMember -ObjectId $GroupObjId -RefObjectId $SaObjId -ErrorAction:Stop
        } catch {
            throw('Failed to add Service Account {0} to Approver Security Group {1}: {2}' -f $saUPN, $GroupName, $_.Exception.Message)
        }
    } else {
        Write-Host('The account {0} is already added to the group {1}' -f $saUPN, $GroupName)
    }
}

# Function to create Azure Logic Apps
function deployLogicApp {
    param (
        [String]$Location,
        [String]$ResourceGroupName,
        [String]$SubscriptionId,
        [String]$SpoSiteName,
        [String]$GroupId,
        [String]$TenantId,
        [String]$ApproverMail,
        [String]$KeyvaultName,
        [String]$AutomationAccountName,
        [String]$AppId,
        [String]$AppSecret,
        [String]$apiConnectionsTemplateJSON,
        [String]$ragTemplateJSON,
        [String]$dcTemplateJSON,
        [String]$teamsTemplateJSON,
        [String]$teamsGroupId, 
        [String]$teamsChannelId

    )
    try { 
        # Deploy API connections
        Write-Host "Deploying API connections..."
        az deployment group create --resource-group $ResourceGroupName --subscription $SubscriptionId --template-file $apiConnectionsTemplateJSON --parameters "subscriptionId=$subscriptionId" "tenantId=$TenantId" "appId=$AppId" "appSecret=$AppSecret" "location=$Location" "keyvaultName=$KeyVaultName"
    } catch {
        throw('Failed to configure Azure API connections: {0}' -f $_.Exception.Message)
    }
    try {
        Write-Host "Deploying logic apps..."

        # Deploy Request-a-Guest Logic Apps
        az deployment group create --resource-group $resourceGroupName --subscription $SubscriptionId --template-file $ragTemplateJSON --parameters "resourceGroupName=$resourceGroupName" "subscriptionId=$subscriptionId" "tenantId=$tenantId" "location=$Location" "spoSiteName=$SpoSiteName" "groupId=$GroupId" "approverMail=$ApproverMail"
        # Deploy Domain Check Logic Apps
        az deployment group create --resource-group $resourceGroupName --subscription $SubscriptionId --template-file $dcTemplateJSON --parameters "resourceGroupName=$resourceGroupName" "subscriptionId=$subscriptionId" "location=$Location" "spoSiteName=$SpoSiteName" "approverMail=$ApproverMail" "AutomationAccountName=$AutomationAccountName"
        # Deploy Teams Approval Logic Apps
        az deployment group create --resource-group $resourceGroupName --subscription $SubscriptionId --template-file $teamsTemplateJSON --parameters "resourceGroupName=$resourceGroupName" "subscriptionId=$subscriptionId" "location=$Location" "spoSiteName=$SpoSiteName" "teamsGroupId=$teamsGroupId" "teamsChannelId=$teamsChannelId"
   
    } catch {
        throw('Failed to configure Azure logic apps: {0}' -f $_.Exception.Message)
    }
}

# Function to create Authentication pop-up
function ShowOAuthWindow($URL) {
    Add-Type -AssemblyName System.Windows.Forms
    $form = New-Object -TypeName System.Windows.Forms.Form -Property @{Width = 600; Height = 800 }
    $web = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{Width = 580; Height = 780; Url = ($url -f ($Scope -join "%20")) }
    $docComp = {
        $Global:uri = $web.Url.AbsoluteUri
        if ($Global:uri -match "error=[^&]*|code=[^&]*") { 
            $form.Close()
        }
    }
    $web.Add_DocumentCompleted($docComp)
    $form.Controls.Add($web)
    $form.Add_Shown( { $form.Activate() })
    $form.ShowDialog() | Out-Null
}

# Function to authorise Logic App connections
function AuthoriseLogicAppConnection($resourceId) {
    $parameters = @{
        "parameters" = , @{
            "parameterName" = "token";
            "redirectUrl"   = "http://localhost"
        }
    }

    # Get the links needed for consent
    $consentResponse = Invoke-AzResourceAction -Action "listConsentLinks" -ResourceId $resourceId -Parameters $parameters -Force

    $url = $consentResponse.Value.Link 

    # Show sign-in prompt window and grab the code after auth
    ShowOAuthWindow -URL $url

    $regex = '(code=)(.*)$'
    $statusCode = ($Global:uri | Select-string -pattern $regex).Matches[0].Groups[2].Value
    # Write-output "Received an accessCode: $code"

    if (-Not [string]::IsNullOrEmpty($statusCode)) {
        $parameters = @{ }
        $parameters.Add("code", $statusCode)
        # NOTE: errors ignored as this appears to error due to a null response
    
        # Confirm the consent code
        Invoke-AzResourceAction -Action "confirmConsentCode" -ResourceId $resourceId -Parameters $parameters -Force -ErrorAction Ignore
    }   

    # Retrieve the connection
    $connection = Get-AzResource -ResourceId $resourceId
    Write-Host "Connection " $connection.Name " now " $connection.Properties.Statuses[0]
}

# Function to consent Logic Apps API Connections
function consentApiConnections {
    param (
        [String]$ServiceAccountUPN,
        [String]$ResourceGroupName
    )

    # API connection names
    $aadApiConnectionName = "requestaguest-azuread"
    $o365ApiConnectionName = "requestaguest-office365"
    $spApiConnectionName = "requestaguest-sharepointonline"
    $aaApiConnectionName = "requestaguest-azureautomation"
    $teamsApiConnectionName = "requestaguest-teams"

    # Create API connection array
    $apiConnections = $aadApiConnectionName, $o365ApiConnectionName, $spApiConnectionName, $aaApiConnectionName, $teamsApiConnectionName

    # Interate thru the api connections and provide consent to them
    foreach ($apiConnection in $apiConnections) {
        $connection = Get-AzResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName -Name $apiConnection -ErrorAction:SilentlyContinue
        Write-Host "Provide consent to API connection $($connection.ResourceId) with user " -NoNewline 
        Write-Host "$($ServiceAccountUPN)" -ForegroundColor Yellow
        AuthoriseLogicAppConnection -resourceId $connection.ResourceId
    }
}

#endregion
#region Configuration Imput Import/ Validation and Module Installation

Write-Host "Starting Request-a-Guest App Deployment`nVersion 1.2 - November 2022" -ForegroundColor Yellow

# Configfiles
$listTemplatePath = Join-Path $PSScriptRoot -ChildPath "\Config\Guests.xml"
$manifest = Join-Path $PSScriptRoot -ChildPath "\Config\manifest.json"
$aaScript = Join-Path $PSScriptRoot -ChildPath "\Scripts\runbook_domain-check.ps1"
$laDcTemplate = Join-Path $PSScriptRoot -ChildPath "\Config\logicapp_domain-check.json"
$laRagTemplate = Join-Path $PSScriptRoot -ChildPath "\Config\logicapp_request-a-guest.json"
$laTeamsTemplate = Join-Path $PSScriptRoot -ChildPath "\Config\logicapp_teams-approval.json"
$apiConnections = Join-Path $PSScriptRoot -ChildPath "\Config\api_connections.json"
$ragConfigfile = Join-Path $PSScriptRoot -ChildPath "\Config\request-a-guest-config.json"

# Check Config files
Write-Host "Check if all required Configuration files exists..."
$reqConfFiles = $listTemplatePath, $manifest, $ragConfigfile, $aaScript, $laDcTemplate, $laRagTemplate, $laTeamsTemplate, $apiConnections
foreach ($confFile in $reqConfFiles) {
    checkIfFileExists -file $confFile
}

# Check for presence of Azure CLI
If (!(Test-Path -Path "C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2")) {
    throw("AZURE CLI not installed!`nPlease visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest")  
}

# Script Variables imported from JSON config-file
$ragConfig = Get-Content $ragConfigfile |ConvertFrom-Json
$SubscriptionId = $ragConfig.Tenant.SubscriptionId
$TenantId = $ragConfig.Tenant.TenantId
$TenantName = $ragConfig.Tenant.TenantName
$Location = $ragConfig.Azure.Location
$AppRegistrationName = $ragConfig.Azure.AppRegistrationName
$ResourceGroup = $ragConfig.Azure.ResourceGroup
$ServiceAccountUPN = $ragConfig.Azure.ServiceAccountUPN
$RequestsSiteName = $ragConfig.SharePointSite.RequestsSiteName
$RequestsSiteDesc = $ragConfig.SharePointSite.RequestsSiteDesc
$ManagedPath = $ragConfig.SharePointSite.ManagedPath
$keyVaultName = (($ragConfig.Azure.KeyVaultName) + (-join (((97..122) | ForEach-Object {[char]$_}) + (0..9) |Get-Random -Count 5)))
$AutomationAccountName = $ragConfig.Azure.AutomationAccountName
$GuestApproverGroup = $ragConfig.Office365.GuestApproverGroup
$GuestRequesterGroup = $ragConfig.Office365.GuestRequesterGroup
$teamsGroupId = $ragConfig.MicrosoftTeams.ApprovalTeamGroupId
$teamsChannelId = $ragConfig.MicrosoftTeams.ApprovalChannelId

# required PS Modules
$preReqModules = "microsoft.online.sharepoint.powershell", "PnP.PowerShell", "Az", "AzureADPreview"

# Install required PS Modules
Write-Host "Check for required PowerShell Modules..."
installModules -Modules $preReqModules
foreach ($module in $preReqModules) {
    $instModule = Get-InstalledModule -Name $module -ErrorAction:SilentlyContinue
    if (!$instModule)  {
        throw('Failed to install module {0}' -f $module)
    }
}

#endregion
#region resource name availablity and provided Azure location

# Connect to Azure
Write-Host 'Connect to Azure Subscription...'
$Error.Clear()
if (!$Mfa) {
    Connect-AzAccount -Credential $creds -Tenant $TenantId -Subscription $SubscriptionId
    if ($error.count -gt 0) {
        throw('Failed to connect to Azure: {0}' -f $_.Exception.Message)
    }
} else {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId
    if ($error.count -gt 0) {
        throw('Failed to connect to Azure: {0}' -f $_.Exception.Message)
    }
}

# Validate provided Azure location
validateAzureLocation -Location $Location

# Check ressource availablity
$resourceParams = @{
    ResourceGroupName = $ResourceGroup
    AppRegistrationName = $AppRegistrationName
    keyVaultName = $keyVaultName
    AutomationAccountName = $AutomationAccountName
}
checkResourceName @resourceParams

#endregion
#region create and configure SharePoint site and Approver Group

# Connect to Azure AD PowerShell
Write-Host 'Connect to Azure AD...'
if (!$Mfa) {
    try {
        Connect-AzureAD -Tenant $TenantId -Credential $creds -ErrorAction:Stop
    } catch {
        throw('Failed to connect to Azure AD: {0}' -f $_.Exception.Message)
    } 
} else {
    try {
        Connect-AzureAD -Tenant $TenantId -ErrorAction:Stop
    } catch {
        throw('Failed to connect to Azure AD: {0}' -f $_.Exception.Message)
    } 
}

# Create approver group
Write-Host('Create Approver Security Group {0}' -f $GuestApproverGroup)
createGroup -GroupName $GuestApproverGroup
Write-Host('Create Approver Security Group {0}' -f $GuestRequesterGroup)
createGroup -GroupName $GuestRequesterGroup
# Wait 30 sec before the next step
Start-Sleep 30

# Add Service account to group
addSaToApproverGroup -GroupName $GuestApproverGroup -saUPN $ServiceAccountUPN

# Create SP access URLs
$tenantAdminUrl = "https://$TenantName-admin.sharepoint.com"

# Remove any spaces in the site name to create the alias
$requestsSiteAlias = $RequestsSiteName -replace (' ', '')
$requestsSiteUrl = "https://$TenantName.sharepoint.com/$ManagedPath/$requestsSiteAlias"

# Create SharePoint Site
Write-Host('Connect to SharePoint Online: {0}' -f $tenantAdminUrl)
try {
    Write-Host "Please enter the Admin Credentials to access the SharePoint site" -ForegroundColor Yellow
    Connect-PnPOnline -Url $tenantAdminUrl -Interactive -ErrorAction:Stop
} catch {
    throw('Failed to connect to SharePoint {0}: {1}' -f $tenantAdminUrl, $_.Exception.Message)
}

$spParams = @{
    spSiteUrl = $requestsSiteUrl
    spSiteName = $RequestsSiteName
    spSiteAlias = $requestsSiteAlias
    spSiteDesc = $RequestsSiteDesc
    saUPN = $ServiceAccountUPN
    listTemplate = $listTemplatePath
    ApproverGroup = $GuestApproverGroup
    RequesterGroup = $GuestRequesterGroup
}
createRequestsSharePointSite @spParams

#endregion
#region Azure Deployment

# Create Azure resource group
createResourceGroup -AzureRgName $ResourceGroup -AzureLocation $Location

# Connect to Azure CLI
Write-Host 'Connect to Azure CLI...'
if (!$Mfa) {
    try {
        az login -u $creds.UserName -p $creds.GetNetworkCredential().Password
    } catch {
        throw('Failed to connect to Azure (AZ): {0}' -f $_.Exception.Message)
    }  
} else {
    try {
        az login
    } catch {
        throw('Failed to connect to Azure (AZ): {0}' -f $_.Exception.Message)
    }
}

# Create Azure App Regiration
Write-Host('Create Azure App Regirstration: {0}' -f $AppRegistrationName)
$appSecret = createAzureADApp -appName $AppRegistrationName -manifestPath $manifest

# Create Azure Automation Account
$AutomationAccountParams = @{
    ResourceGroup = $ResourceGroup
    AutomationAccount = $AutomationAccountName
    DomainCheckScript = $aaScript
    Location = $Location
    ServiceAccountUPN = $ServiceAccountUPN
    ServiceAccountPwd = $ServiceAccountPwd
}
createAutomationAccount @AutomationAccountParams

# Configure Azure Key Vault
Write-Host('Create Azure Key Vault: {0}' -f $keyVaultName)
$vaultParams = @{
    KeyVaultName = $keyVaultName
    ResourceGroupName = $ResourceGroup
    Location = $Location
    appName = $AppRegistrationName
    appSecret = $appSecret
}
createConfigureKeyVault @vaultParams

Write-Host('Grant "Owner" access to service account {0}...' -f $ServiceAccountUPN)

# Wait 20 sec for the resource creation
Start-Sleep 20

# Grant contributor access to Azure Key Vault
$valutAccessParams = @{
    subscriptionId = $subscriptionId
    ServiceAccountUPN = $ServiceAccountUPN
    Scope = "/providers/Microsoft.KeyVault/vaults/"
    Resource = $KeyvaultName
    ResourceGroupName = $ResourceGroup
}
grantAzureKvPermissionToServiceAcount @valutAccessParams
# Grant contributor access to Azure Automation Account
$automationAccountAccessParams = @{
    subscriptionId = $subscriptionId
    ServiceAccountUPN = $ServiceAccountUPN
    Scope = "/providers/Microsoft.Automation/automationAccounts/"
    Resource = $AutomationAccountName
    ResourceGroupName = $ResourceGroup
}
grantAzureAaPermissionToServiceAcount @automationAccountAccessParams

Write-Host('Get Approver Security Group {0}' -f $GuestApproverGroup)
$ApproverGroup = getGroup -GroupName $GuestApproverGroup

# Install API Connections and Logic Apps
$logicappParams = @{
    ResourceGroupName = $ResourceGroup
    SubscriptionId = $SubscriptionId
    apiConnectionsTemplateJSON = $apiConnections
    ragTemplateJSON = $laRagTemplate
    dcTemplateJSON = $laDcTemplate
    teamsTemplateJSON = $laTeamsTemplate
    teamsGroupId = $teamsGroupId
    teamsChannelId = $teamsChannelId
    TenantId = $TenantId
    AppId = (getAzureADApp -Name $AppRegistrationName).appId
    AppSecret = $appSecret
    Location = $Location
    KeyVaultName = $keyVaultName
    AutomationAccountName = $AutomationAccountName
    ApproverMail = $ServiceAccountUPN
    GroupId = $ApproverGroup
    SpoSiteName = $requestsSiteUrl
}
deployLogicApp @logicappParams

# Consent API Connections for the Logic Apps
Write-Host "Now you need to provide constent to the API Connections inside the Logic Apps `nPlease enter the credentials of the Service Account " -NoNewline
Write-Host "$($ServiceAccountUPN)" -ForegroundColor Yellow
consentApiConnections -ServiceAccountUPN $ServiceAccountUPN -ResourceGroupName $ResourceGroup

#endregion
#region clean-up

# Clear Passwords and Credentials from variables
$Adminpwd = $null
$creds = $null
$ServiceAccountPwd = $null
$appSecret = $null

#endregion

Write-Host "Successful deployed Request-a-Guest App.`nThe following values are required for the Power App:" -ForegroundColor Green
Write-Host "SharePoint Site: " -NoNewline
Write-Host "$($requestsSiteUrl)" -ForegroundColor Yellow
Write-Host "Approver Group ID: " -NoNewline
Write-Host "$($ApproverGroup)" -ForegroundColor Yellow
