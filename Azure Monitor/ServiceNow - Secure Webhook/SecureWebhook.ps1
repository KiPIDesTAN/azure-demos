#   Author: Adam Newhard - adam@adamnewhard.com
#   URL: https://github.com/KiPIDesTAN and www.adamnewhard.com

# This code is based on PowerShell code available from https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups#secure-webhook-powershell-script
# This code is different from the referenced link in that it leverages the PowerShell Az.Resource module as opposed to the AzureAD module.
# This code assumes you are already authenticated to your tenant with Connect-AzAccount and have access to modify AAD.

# Define your Azure AD application's ObjectId.
$myAzureADApplicationObjectId = "<app registration object id>"

# Define the action group Azure AD AppId. This is the app ID of the Azns AAD Webhook account.
$actionGroupsAppId = "461e8683-5575-4561-ac7f-899cc907d62a"

# Define the name of the new role that gets added to your Azure AD application.
$actionGroupRoleName = "ActionGroupsSecureWebhook"

# Get your Azure AD application, its roles, and its service principal.
$myApp = Get-AzADApplication -ObjectId $myAzureADApplicationObjectId

$myAppRoles = $myApp.AppRole
$actionGroupsSP = Get-AzADServicePrincipal -Filter ("appId eq '" + $actionGroupsAppId + "'")
 
Write-Host "App Roles before addition of new role.."
Write-Host $myAppRoles

# Create the role if it doesn't exist.
if ($myAppRoles -match "ActionGroupsSecureWebhook")
{
    Write-Host "The Action Group role is already defined.`n"
}
else
{
    $myServicePrincipal = Get-AzADServicePrincipal -Filter ("appId eq '" + $myApp.AppId + "'")

    # Add the new role to the Azure AD application.
    $myAppRoles += @{
        DisplayName = $actionGroupRoleName
        Description = "This is a role for Action Group to join"
        Id = (New-Guid).Guid
        IsEnabled = $true
        Value = $actionGroupRoleName
        AllowedMemberType = @('Application')
    }

    Update-AzADApplication -ObjectId $myApp.Id -AppRole $myAppRoles

    # Refresh the app roles
    $myApp = Get-AzADApplication -ObjectId $myAzureADApplicationObjectId
    $myAppRoles = $myApp.AppRole
}

# Create the service principal if it doesn't exist.
if ($actionGroupsSP -match "AzNS AAD Webhook")
{
    Write-Host "The Service principal is already defined.`n"
}
else
{
    # Create a service principal for the action group Azure AD application and add it to the role.
    $actionGroupsSP = New-AzADServicePrincipal -ApplicationId $actionGroupsAppId
}

# Get the Id of the $actionGroupRoleName role.
# From https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments?view=graph-rest-1.0&tabs=http
$id = $myApp.AppRole | Where-Object { $_.DisplayName -eq $actionGroupRoleName } | Select-Object -ExpandProperty Id # appRoleId
$objectId = $actionGroupsSP.Id       # Id that goes into the URL of the Invoke-AzRestMethod call

$body = @{
    principalId = $actionGroupsSP.Id
    resourceId = $myServicePrincipal.Id
    appRoleId = $id
}

Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$objectId/appRoleAssignments" -Method POST -Payload ($body | ConvertTo-Json)

Write-Host "My Azure AD Application (ObjectId): " + $myApp.Id
Write-Host "My Azure AD Application's Roles"
Write-Host $myApp.AppRole