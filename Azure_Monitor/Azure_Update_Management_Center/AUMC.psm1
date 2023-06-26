###################################
# Author: Adam Newhard
# URL: https://github.com/KiPIDesTAN/azure-demos
#
# This file is an implementation of the Azure Update Management Center REST API and other 
# functionality available via the Azure Portal. This code is based on the REST API available at
# https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
#
# Requirements:
# 1. Azure PowerShell module. Install-Module Az
# 2. Connect to Azure. Connect-AzAccount
###################################

function Invoke-AUMCAssessment {
    <#
    .SYNOPSIS
    Starts an update assessment.
    .DESCRIPTION
    Starts an update assessment for a single VM within Azure Update Management Center. The cmdlet will wait for the completion of the assessment by default
    and return a list of all the packages or KBs that are available for the VM. If -NoWait is set, the cmdlet will not wait and nothing will be returned.
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be assessed.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be assessed.
    .PARAMETER VMName
    Name of the VM to be assessed.
    .PARAMETER NoWait
    When set, the cmdlet won't wait for the assessment to complete and will immediately return. Will wait for the assessment to complete when not set.
    .EXAMPLE
    Invoke-AUMCAssessment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM
    .EXAMPLE
    Invoke-AUMCAssessment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -NoWait
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$false)]
        [Switch]$NoWait
	)


    # Execute a machine assessment
    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/assessPatches?api-version=2020-12-01" -Method POST -Payload '{}'

    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }

    if (!$NoWait) {
        # Poll the resource graph API for the completion of the assessment
        # Query Az.ResourceGraph for the status of the assessment
        $assessmentQuery = "patchassessmentresources
        | where id =~ `"/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchAssessmentResults/latest`"
        | extend operationType = iff (properties.startedBy =~ `"Platform`", `"AzureOrchestrated`", `"ManualAssessment`")
        | extend endTime = iff(properties.status =~ `"InProgress`" or properties.status =~ `"NotStarted`", datetime(null), todatetime(properties.lastModifiedDateTime))
        | project id, operationId = properties.assessmentActivityId, assessmentStatus = properties.status, updateOperation = `"Assessment`", operationType, startTime = properties.startDateTime, endTime, properties"

        $assessmentStartTime = Get-Date -AsUTC
        $assessmentStarted = $false
        # We want to execute this loop until $queryResults.assessmentStatus -ne "InProgress". If the assessmentStatus eq "Succeeded", we can move on.
        do
        {
            Write-Verbose "Polling for assessment completion."
            Start-Sleep -Seconds 30 # During the first iteration, it may take up to 30 seconds for the assessment to start and update in the Resource Graph.
            $queryResults = Search-AzGraph -Query $assessmentQuery -Subscription $SubscriptionId
            # Sometimes an assessment will not start within the first 30 seconds. We use the start time returned by the graph API to make sure that the startTime is greater than the time we initially started our assessment execution request to know that the assessment really started.
            if ($assessmentStartTime -lt $queryResults.startTime -and !$assessmentStarted) {
                Write-Verbose "Legitimate assessment found."
                $assessmentStarted = $true
            }
            Write-Verbose "Operation Id: $($queryResults.operationId) Status: $($queryResults.assessmentStatus)"
        } while ($queryResults.assessmentStatus -eq "InProgress" -or !$assessmentStarted)

        return $queryResults
    }
}

function Get-AUMCAssessmentPatches {
    <#
    .SYNOPSIS
    Gets the latest assessment
    .DESCRIPTION
    Gets the list of the patches discovered during the latest assessment. The id and the properties JSON is returned. This should probably be cleaned up to return discrete
    information in the future.
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be assessed.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be assessed.
    .PARAMETER VMName
    Name of the VM to be assessed.
    .EXAMPLE
    Get-AUMCAssessmentPatches -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName
	)

    $patchListQuery = "patchassessmentresources
                | where type =~ `"microsoft.compute/virtualmachines/patchAssessmentResults/softwarePatches`"
                | where id startswith `"/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchAssessmentResults/latest/softwarePatches/`"
                | project id, properties"

    $queryResults = Search-AzGraph -Query $patchListQuery -Subscription $SubscriptionId

    # Show the list of patches available
    [PSObject[]]$queryResults.properties
}

function Invoke-AUMCOneTimeDeployment {
    <#
    .SYNOPSIS
    Invokes a one time deployment based on the parameteres provided.
    .DESCRIPTION
    Deploys a series of patches to the target VM based on criteria passed as parameters
    .PARAMETER Linux
    Identifies the VM to be patched is Linux
    .PARAMETER Windows
    Identifies the VM to be patched is Windows
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be assessed.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be assessed.
    .PARAMETER VMName
    Name of the VM to be assessed.
    .PARAMETER MaximumDuration
    Maximum duration of the deployment. The value passed here is an ISO 8601-compliant duration. Defaults to PT120M, which is 120 minutes.
    .PARAMETER RebootSettings
    Reboot options post-deployment. Valid values are IfRequired, NeverReboot, or AlwaysReboot. IfRequired is the default.
    .PARAMETER ClassificationsToInclude
    Patch classificiations to deploy.
    .PARAMETER PackageNameMasksToInclude
    Array of package masks for inclusion during deployment. Applies when -Linux is passed on the command line.
    .PARAMETER PackageNameMasksToExclude
    Array of package masks for exclusion during deployment. Applies when -Linux is passed on the command line.
    .PARAMETER KbNumbersToInclude
    Array of KBs for inclusion during deployment. Applies when -Windows is passed on the command line.
    .PARAMETER KbNumbersToExclude
    Array of KBs for exclusion during deployment. Applies when -Windows is passed on the command line.
    .PARAMETER NoWait
    When set, the cmdlet won't wait for the assessment to complete and will immediately return. Will wait for the assessment to complete when not set.
    .EXAMPLE
    Invoke-AUMCOneTimeDeployment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -Linux -Classifications "Other"
    .EXAMPLE
    Invoke-AUMCOneTimeDeployment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -Linux -Classifications "Other" -PackageNameMasksToInclude "libcurl*", "python3*" -MaximumDuration PT60M
    .EXAMPLE
    Invoke-AUMCOneTimeDeployment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -Windows -Classifications "Security", "Maintenance"
    .EXAMPLE
    Invoke-AUMCOneTimeDeployment -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -Windows -KbNumbersToInclude 2341243 -NoWait
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    .LINK
    https://learn.microsoft.com/en-us/rest/api/compute/virtual-machines/install-patches
    #>
    [CmdletBinding(SupportsShouldProcess=$True,DefaultParameterSetName='Linux')]
	param(
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
        [Switch]$Linux,
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
        [Switch]$Windows,
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$false)]
        [string]$MaximumDuration = 'PT120M', # ISO 8601-compliant duration
        [Parameter(Mandatory=$false)]
        [ValidateSet('IfRequired','NeverReboot', 'AlwaysReboot')]
        [string]$RebootSetting = 'IfRequired',
        [Parameter(Mandatory=$false)]
		[string[]]$ClassificationsToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
		[string[]]$PackageNameMasksToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
		[string[]]$PackageNameMasksToExclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
		[string[]]$KbNumbersToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
		[string[]]$KbNumbersToExclude = @(),
        [Parameter(Mandatory=$false)]
        [Switch]$NoWait
	)

    $deploymentPayload = @{
        maximumDuration = $MaximumDuration
        rebootSetting = $RebootSetting
    }   

    if ($Linux) {
        $deploymentPayload["linuxParameters"] = @{
                classificationsToInclude = $ClassificationsToInclude
                packageNameMasksToInclude = $PackageNameMasksToInclude
                packageNameMasksToExclude = $PackageNameMasksToExclude
            }
    }
    if ($Windows) {
        $deploymentPayload["windowsParameters"] = @{
                classificationsToInclude = $ClassificationsToInclude
                kbNumbersToInclude = $KbNumbersToInclude
                kbNumbersToExclude = $KbNumbersToExclude
            }
    }

    Write-Verbose "Deployment Payload"
    Write-Verbose ($deploymentPayload | ConvertTo-Json -Depth 10)

    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/installPatches?api-version=2022-08-01" -Method POST -Payload ($deploymentPayload | ConvertTo-Json -Depth 10)
 
    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return 1
    }

    Write-Verbose "One-Time Deployment initiated."

    if (!$NoWait) {
        # Get the status of the on-demand update. Note that this query was updated to change the last line from order by startTime desc to top 1 by startTime desc. We only need a single deployment returned with this query to check the status.
        $deploymentStatusQuery = "patchinstallationresources
        | where type in~ (`"microsoft.hybridcompute/machines/patchinstallationresults`", `"microsoft.compute/virtualmachines/patchinstallationresults`")
        | where properties.startDateTime > ago(30d)
        | where id startswith `"/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchInstallationResults/`"
        | extend updateDeploymentStatus = tostring(properties.status)
        | project maintenanceRunId = tolower(properties.maintenanceRunId), updateDeploymentStatus, properties, id, name
        | join kind=leftouter (
            maintenanceresources
            | where type =~ `"microsoft.maintenance/applyupdates`"
            | where properties.startDateTime > ago(30d) - 6h
            | where properties.resourceId =~ `"/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName`"
            | where properties.maintenanceScope =~ `"InGuestPatch`"
            | project maintenanceRunIdFromMrp = tolower(properties.correlationId)
        ) on `$left.maintenanceRunId == `$right.maintenanceRunIdFromMrp
        | where isempty(maintenanceRunIdFromMrp) == true
        | project-away maintenanceRunId, maintenanceRunIdFromMrp
        | extend startTime = todatetime(properties.startDateTime)
        | extend endTime = iff(updateDeploymentStatus =~ `"InProgress`" or updateDeploymentStatus =~ `"NotStarted`", datetime(null), todatetime(properties.lastModifiedDateTime))
        | extend installedPatchesCount = iff(isnotnull(properties.installedPatchCount), properties.installedPatchCount, 0)
        | extend totalPatchesCount = installedPatchesCount + iff(isnotnull(properties.notSelectedPatchCount), properties.notSelectedPatchCount, 0) + iff(isnotnull(properties.excludedPatchCount), properties.excludedPatchCount, 0) + iff(isnotnull(properties.pendingPatchCount), properties.pendingPatchCount, 0) + iff(isnotnull(properties.failedPatchCount), properties.failedPatchCount, 0)
        | extend operationId = name
        | extend operationType = iff (properties.startedBy =~ `"Platform`", `"AzureOrchestrated`", `"ManualUpdates`")
        | extend updateOperation = `"InstallUpdate`"
        | project id, operationId, updateDeploymentStatus, installedPatchesCount, totalPatchesCount, updateOperation, operationType, startTime, endTime
        | top 1 by startTime desc"

        # We want to execute this loop until $queryResults.updateDeploymentStatus -ne "InProgress". If the updateDeploymentStatus eq "Succeeded", we can move on.
        $deploymentStartTime = Get-Date -AsUTC
        $deploymentStarted = $false
        do
        {
            Write-Verbose "Polling for deployment completion."
            Start-Sleep -Seconds 30 # During the first iteration, it may take up to 30 seconds for the update to start and update in the Resource Graph

            # Get the status of the deployment. We want to find the most recent deployment for the resource. This is the first record returned, which is part of the filter in the query itself.
            $queryResults = Search-AzGraph -Query $deploymentStatusQuery -Subscription $SubscriptionId
             # Sometimes an deployment will not start within the first 30 seconds. We use the start time returned by the graph API to make sure that the startTime is greater than the time we initially started our assessment execution request to know that the assessment really started.
             if ($deploymentStartTime -lt $queryResults.startTime -and !$deploymentStarted) {
                Write-Verbose "Legitimate assessment found."
                $deploymentStartTime = $true
            }
            Write-Verbose "Operation Id: $($queryResults.operationId) Status: $($queryResults.updateDeploymentStatus)"
        } while ($queryResults.updateDeploymentStatus -eq "InProgress" -or !$deploymentStarted)
        
        return $queryResults
    }
}

function Get-AUMCDeploymentActivities {
    <#
    .SYNOPSIS
    Returns a list of all the deployment activites.
    .DESCRIPTION
    Returns a list of all the deployemnt activities that occurred during a given operationId. The list includes all the patches that were available as assessed packages during the deployment and identifies
    which of those packages were installed.
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be assessed.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be assessed.
    .PARAMETER VMName
    Name of the VM to be assessed.
    .PARAMETER OperationId
    GUID uniquely representing the deployment
    .EXAMPLE
    Get-AUMCDeploymentActivities -SubscriptionId 11111-11111-11111-11111-111111 -ResourceGroup MyResourceGroup -VMName MyVM -OperationId 22222-22222-22222-22222-22222
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$true)]
        [string]$OperationId
	)
    # Each query result will come with an operationId. That Id can be used with the following query to get a list of the events that occurred during the deployment operation.
    $deploymentOperationsQuery = "PatchInstallationResources 
                                    | where type =~ 'microsoft.compute/virtualmachines/patchInstallationResults/softwarePatches'
                                    | where id contains '/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchInstallationResults/$OperationId/softwarePatches/'
                                    | project properties, id"

    $queryResults = Search-AzGraph -Query $deploymentOperationsQuery -Subscription $SubscriptionId

    # Output the list of patches that were "available" during the deployment, including if they were installed, classification, patchName, and version of the patch
    [PSObject[]]$queryResults.properties
}

function Get-AUMCDeploymentHistory {
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName
	)
    # Each query result will come with an operationId. That Id can be used with the following query to get a list of the events that occurred during the deployment operation.
    # TODO: Add a date lookback filter to limit how far back the history is shared
    $deploymentHistoryQuery = "PatchInstallationResources 
                                    | where type =~ 'microsoft.compute/virtualmachines/patchInstallationResults/softwarePatches'
                                    | where id contains '/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchInstallationResults/'
                                    | extend jsonProperties = parse_json(properties)
                                    | extend lastModifiedDateTime = todatetime(jsonProperties.lastModifiedDateTime), patchName = tostring(jsonProperties.patchName)
                                    | summarize arg_max(lastModifiedDateTime, *) by patchName
                                    | project lastModifiedDateTime, classifications = jsonProperties.classifications, patchName, patchId = tostring(name), version = tostring(jsonProperties.version), kbId = tostring(jsonProperties.kbId), installationState = tostring(jsonProperties.installationState)"

    $queryResults = Search-AzGraph -Query $deploymentHistoryQuery -Subscription $SubscriptionId

    # Cast to a PSObject[]. Otherwise, commands like Compare-Object will fail, even when comparing just a single string property
    [PSObject[]]$queryResults
}

function New-AUMCMaintenanceConfiguration {
    <#
    .SYNOPSIS
    Creates a new mainteinance configuration
    .DESCRIPTION
    Returns a list of all the deployemnt activities that occurred during a given operationId. The list includes all the patches that were available as assessed packages during the deployment and identifies
    which of those packages were installed.
    .PARAMETER SubscriptionId
    Subscription Id where the maintenance configuration will be created.
    .PARAMETER ResourceGroup
    Resource group name where the maintenance configuration will be created.
    .PARAMETER MaintenanceConfigurationName
    Name of the maintenance configuration
    .PARAMETER MaintenancePayload
    Payload of the mainteinance configuration to be created.
    TODO: This should be converted to take the actual input parameters and use the latest API
    .EXAMPLE
    TODO: Add an example once the MaintenancePayload is broken out into its individual parts.
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
        [string]$MaintenanceConfigurationName,
        [Parameter(Mandatory=$true)]
        [string]$MaintenancePayload
	)

    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Maintenance/maintenanceConfigurations/$($MaintenanceConfigurationName)?api-version=2021-09-01-preview" -Method PUT -Payload $MaintenancePayload
    
    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }

    return $restResult.Content
}

function Add-AUMCConfigurationAssignment {
     <#
    .SYNOPSIS
    Assigns a VM to a maintenance configuration
    .DESCRIPTION
    Assigns a VM to a maintenance configuration
    .PARAMETER SubscriptionId
    Subscription Id of the target VM.
    .PARAMETER ResourceGroup
    Resource group name of the target VM.
    .PARAMETER VMName
    Name of the target VM.
    .PARAMETER ConfigurationAssignmentName
    Name of the configuration assignment
    .PARAMETER ConfigurationAssignmentPayload
    Configuration assignment JSON payload.
    TODO: Update the ConfigurationAssignmentPayload to break it into the discrete values.
    .EXAMPLE
    TODO: Add an example once the ConfigurationAssignmentPayload is broken down into its discrete parts
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$true)]
        [string]$ConfigurationAssignmentName,
        [Parameter(Mandatory=$true)]
        [string]$ConfigurationAssignmentPayload
	)

    # TODO: Validate we are using the latest API version
    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/providers/Microsoft.Maintenance/configurationAssignments/$($ConfigurationAssignmentName)?api-version=2021-09-01-preview" -Method PUT -Payload $ConfigurationAssignmentPayload

    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }
    return $restResult.Content
}

function Get-AUMCVMUpdateSettings {
    <#
    .SYNOPSIS
    Gets the current update settings for a VM.
    .DESCRIPTION
    Gets the current update settings for a VM. Null is returned if no settings are found.
    .PARAMETER SubscriptionId
    Subscription Id of the target VM.
    .PARAMETER ResourceGroup
    Resource group name of the target VM.
    .PARAMETER VMName
    Name of the target VM.
    .EXAMPLE
    Get-AUMCVMUpdateSettings -SubscriptionId 11111-11111-11111-11111-11111 -ResourceGroup MyResourceGroup -VMName MyVM
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName
    )

    $vmJson = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)?api-version=2022-11-01" -Method GET
    $vm = $vmJson.Content | ConvertFrom-Json

    if ($vm.properties.storageProfile.osDisk.osType -eq 'Linux') {
        return $vm.properties.osProfile.linuxConfiguration.patchSettings
    }
    elseif ($vm.properties.storageProfile.osDisk.osType -eq 'Windows') {
        return $vm.properties.osProfile.windowsConfiguration.patchSettings
    }
    return $null
}

function Set-AUMCVMUpdateSettings {
    <#
    .SYNOPSIS
    Set the update settings for a VM.
    .DESCRIPTION
    Set the assessment mode, patch mode, and hotpatching functionality for a VM.
    .PARAMETER SubscriptionId
    Subscription Id of the target VM.
    .PARAMETER ResourceGroup
    Resource group name of the target VM.
    .PARAMETER VMName
    Name of the target VM.
    .PARAMETER AssessmentMode
    Method of assessment for updates. Valid valuse are AutomaticByPlatform or ImageDefault.
    .PARAMETER PatchMode
    Method of patching. Valid valuse are AutomaticByPlatform, AutomaticByOS, Manual, ImageDefault.
    .PARAMETER Hotpatching
    Enables or disables the ability to hotpatch a system. Valued values are Enabled or Disabled.
    .EXAMPLE
    Get-AUMCVMUpdateSettings -SubscriptionId 11111-11111-11111-11111-11111 -ResourceGroup MyResourceGroup -VMName MyVM
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically
    .LINK
    https://learn.microsoft.com/en-us/dotnet/api/microsoft.azure.management.compute.models.patchsettings.assessmentmode?view=azure-dotnet
    .LINK
    https://learn.microsoft.com/en-us/azure/virtual-machines/automatic-vm-guest-patching#patch-orchestration-modes
    .LINK
    https://learn.microsoft.com/en-us/azure/automanage/automanage-hotpatch
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
        [Switch]$Linux,
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
        [Switch]$Windows,
		[Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$false)]
        [ValidateSet('AutomaticByPlatform', 'ImageDefault')]
        [string]$AssessmentMode,
        [Parameter(Mandatory=$false)]
        [ValidateSet('AutomaticByPlatform', 'AutomaticByOS','Manual','ImageDefault')]
        [string]$PatchMode,
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
        [ValidateSet('Enabled', 'Disabled')]
        [string]$Hotpatching
	)

    if ([String]::IsNullOrWhiteSpace($AssessmentMode) -and [String]::IsNullOrWhiteSpace($PatchMode) -and [String]::IsNullOrWhiteSpace($Hotpatching)) {
        throw "At least one of AssessmentMode, PatchMode, or Hotpatching must be set."
    }
    
    # Get the VM profile so we can create the appropriate payload
    $vmJson = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)?api-version=2022-11-01" -Method GET
    $vm = $vmJson.Content | ConvertFrom-Json

    # Go down each path for the osType
    if ($vm.properties.storageProfile.osDisk.osType -eq 'Linux') {
        if ($PatchMode -in @('AutomaticByOS','Manual')) {
            throw "$PatchMode patch orchestration is only available on Windows."
        }

        # Create a genereic payload
        $payLoad = @{
            location = $vm.location
            properties = @{
                osProfile = @{
                    linuxConfiguration = @{
                        patchSettings = @{}
                    }
                }
            }
        }

        if (![String]::IsNullOrWhiteSpace($AssessmentMode)) {
            $payLoad.properties.osProfile.linuxConfiguration.patchSettings["assessmentMode"] = $AssessmentMode
        }
        if (![String]::IsNullOrWhiteSpace($PatchMode)) {
            $payLoad.properties.osProfile.linuxConfiguration.patchSettings["patchMode"] = $PatchMode
        }
    }
    elseif ($vm.properties.storageProfile.osDisk.osType -eq 'Windows') {
        # Create a genereic payload
        $payLoad = @{
            location = $vm.location
            properties = @{
                osProfile = @{
                    windowsConfiguration = @{
                        patchSettings = @{}
                    }
                }
            }
        }

        if (![String]::IsNullOrWhiteSpace($AssessmentMode)) {
            $payLoad.properties.osProfile.windowsConfiguration.patchSettings["assessmentMode"] = $AssessmentMode
        }
        if (![String]::IsNullOrWhiteSpace($PatchMode)) {
            $payLoad.properties.osProfile.windowsConfiguration.patchSettings["patchMode"] = $PatchMode
        }
        if (![String]::IsNullOrWhiteSpace($HotPatching)) {
            $payLoad.properties.osProfile.windowsConfiguration.patchSettings["enableHotpatching"] = if ($Hotpatching -eq 'Enabled') { $true } else { $false }
        }
    }

    # NOTE: We use the direct REST API command instead of Set-AzVMOperatingSystem so we don't need to pull a PSCredential object.
    $restResult = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)?api-version=2022-11-01" -Method PUT -Payload ($payLoad | ConvertTo-Json -Depth 10)
    
    if ($restResult.StatusCode -ne 200) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }

    return $restResult.Content
}

function New-AUMCMaintenanceConfigurationSchedule {
    <#
    .SYNOPSIS
    Creates a new maintenance configuration schedule in Azure Update Management Center.
    .DESCRIPTION
    Creates a new maintenance configuration schedule in Azure Update Management Center.
    .PARAMETER Linux
    When set, the cmdlet will create a maintenance configuration schedule for Linux VMs.
    .PARAMETER Windows
    When set, the cmdlet will create a maintenance configuration schedule for Windows VMs.
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be assessed.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be assessed.
    .PARAMETER MaintenanceConfigurationName
    Name of the maintenance configuration to be created.
    .PARAMETER Location
    Location where the maintenance configuration will be created.
    .PARAMETER ExtensionProperties
    A hashtable of extension properties to be passed to the maintenance configuration.
    .PARAMETER MaintenanceScope
    The maintenance scope.
    .PARAMETER MaintenanceWindow
    The maintenance window for the schedule. This is a hash table of startDateTime, expirationDateTime, duration, timeZone, and recurEvery.
    .PARAMETER RebootSetting
    The reboot setting for the schedule. Valid values are IfRequired, Never, and Always. Defaults to IfRequired.
    .PARAMETER ClassificationsToInclude
    Patch classificiations to deploy.
    .PARAMETER PackageNameMasksToInclude
    Array of package masks for inclusion during deployment. Applies when -Linux is passed on the command line.
    .PARAMETER PackageNameMasksToExclude
    Array of package masks for exclusion during deployment. Applies when -Linux is passed on the command line.
    .PARAMETER KbNumbersToInclude
    Array of KBs for inclusion during deployment. Applies when -Windows is passed on the command line.
    .PARAMETER KbNumbersToExclude
    # TODO: Add example invocations.
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically?tabs=cli%2Crest#create-a-maintenance-configuration-schedule
    #>
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
        [Switch]$Linux,
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
        [Switch]$Windows,
        [Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$MaintenanceConfigurationName,
        [Parameter(Mandatory=$true)]
		[string]$Location,
        $ExtensionProperties,           # TODO: Add more information about this parameter
        [string]$MaintenanceScope,      # TODO: Add the valid set.
        [Parameter(Mandatory=$true)]
        $MaintenanceWindow,             # TODO: This is presently a hash table and should be expanded to individual fields.
        [Parameter(Mandatory=$false)]
        [ValidateSet('IfRequired','NeverReboot', 'AlwaysReboot')]
        [string]$RebootSetting = 'IfRequired',
        [Parameter(Mandatory=$false)]
		[string[]]$ClassificationsToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
		[string[]]$PackageNameMasksToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Linux')]
		[string[]]$PackageNameMasksToExclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
		[string[]]$KbNumbersToInclude = @(),
        [Parameter(Mandatory=$false,ParameterSetName='Windows')]
		[string[]]$KbNumbersToExclude = @()
	)

    $payload = @{
        location = $Location
        properties = @{
            extensionProperties = $ExtensionProperties
            maintenanceScope = $MaintenanceScope
            maintenanceWindow = $MaintenanceWindow
            installPatches = @{
                rebootSetting = $RebootSetting
            }
        }
    }   

    if ($Linux) {
        $payload.properties.installPatches["linuxParameters"] = @{
                classificationsToInclude = $ClassificationsToInclude
                packageNameMasksToInclude = $PackageNameMasksToInclude
                packageNameMasksToExclude = $PackageNameMasksToExclude
            }
    }
    if ($Windows) {
        $payload.properties.installPatches["windowsParameters"] = @{
                classificationsToInclude = $ClassificationsToInclude
                kbNumbersToInclude = $KbNumbersToInclude
                kbNumbersToExclude = $KbNumbersToExclude
            }
    }

    Write-Verbose "Payload"
    Write-Verbose  ($payload | ConvertTo-Json -Depth 10)

    # https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically?tabs=cli%2Crest#create-a-maintenance-configuration-schedule
    # PUT on `/subscriptions/<subscriptionId>/resourceGroups/<resourceGroup>/providers/Microsoft.Maintenance/maintenanceConfigurations/<maintenanceConfigurationsName>?api-version=2021-09-01-preview`
    $restResult = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Maintenance/maintenanceConfigurations/$($MaintenanceConfigurationName)?api-version=2021-09-01-preview" -Method PUT -Payload ($payLoad | ConvertTo-Json -Depth 10)

    if ($restResult.StatusCode -ne 200) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }

    return $restResult.Content
}

function Set-AUMCVMMaintenanceScheduleAssociation {
    <#
    .SYNOPSIS
    Associate a VM with a maintenance configuration schedule.
    .DESCRIPTION
    Associates a VM with a maintenance configuration schedule.
    .PARAMETER SubscriptionId
    Subscription Id of the VM to be associated with the schedule.
    .PARAMETER ResourceGroup
    Resource group name of the VM to be associated with the schedule.
    .PARAMETER VMName
    Name of the VM to be associated with the schedule.
    .PARAMETER MaintenanceConfigurationName
    Name of the maintenance configuration to be associated with the VM.
    .PARAMETER Location
    Location where the VM to maintenance configuration association will be created.
    # TODO: Add example invocations.
    .LINK
    https://github.com/KiPIDesTAN/azure-demos
    .LINK
    https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically?tabs=cli%2Crest#associate-a-vm-with-a-schedule
    #>
	param(
        [Parameter(Mandatory=$true)]
		[string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
		[string]$ResourceGroup,
        [Parameter(Mandatory=$true)]
		[string]$VMName,
        [Parameter(Mandatory=$true)]
		[string]$MaintenanceConfigurationName,
        [Parameter(Mandatory=$true)]
		[string]$Location
	)

    $payload = @{
        location = $Location
        properties = @{
            maintenanceConfigurationId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Maintenance/maintenanceConfigurations/$($MaintenanceConfigurationName)"
        }
    }

    # https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically?tabs=cli%2Crest#associate-a-vm-with-a-schedule
    # PUT on `<ARC or Azure VM resourceId>/providers/Microsoft.Maintenance/configurationAssignments/<configurationAssignment name>?api-version=2021-09-01-preview`
    $restResult = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)/providers/Microsoft.Maintenance/configurationAssignments/$($MaintenanceConfigurationName)?api-version=2021-09-01-preview" -Method PUT -Payload ($payLoad | ConvertTo-Json -Depth 10)

    if ($restResult.StatusCode -ne 200) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $restResult.Content
    }

    return $restResult.Content
}

# TODO: Remove machine from a schedule https://learn.microsoft.com/en-us/azure/update-center/manage-vms-programmatically?tabs=cli%2Crest#remove-machine-from-the-schedule

Export-ModuleMember -Function New-AUMCMaintenanceConfiguration
Export-ModuleMember -Function Add-AUMCConfigurationAssignment
Export-ModuleMember -Function Invoke-AUMCAssessment, Invoke-AUMCOneTimeDeployment
Export-ModuleMember -Function Get-AUMCAssessmentPatches, Get-AUMCDeploymentActivities, Get-AUMCDeploymentHistory, Get-AUMCVMUpdateSettings
Export-ModuleMember -Function Set-AUMCVMUpdateSettings, Set-AUMCVMMaintenanceScheduleAssociation
