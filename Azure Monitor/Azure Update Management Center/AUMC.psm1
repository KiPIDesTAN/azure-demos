###################################
# This file is a port of the V1-Create-azUpdatePatchDeploymentList-Sch-Ena-Dis.ps1 file
# that was utilized for Azure Automation Update Management. This script is a port to work with
# Azure Update Management Center, in preview at the time of this file's creation.
#
# While this file attempts to implement all that was available in the AAUM version, it cannot do 
# everything due to differences in the script. Those differencesa are documented below as a working
# record.
###################################

function Invoke-AUMCAssessment {
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
    # az rest --method post --url https://management.azure.com/subscriptions/subscriptionId/resourceGroups/resourceGroupName/providers/Microsoft.Compute/virtualMachines/virtualMachineName/assessPatches?api-version=2020-12-01
    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/assessPatches?api-version=2020-12-01" -Method POST -Payload '{}'

    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return 1
    }

    if (!$NoWait) {
        # Poll the resource graph API for the completion of the assessment
        # Query Az.ResourceGraph for the status of the assessment
        $assessmentQuery = "patchassessmentresources
        | where id =~ `"/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/patchAssessmentResults/latest`"
        | extend operationType = iff (properties.startedBy =~ `"Platform`", `"AzureOrchestrated`", `"ManualAssessment`")
        | extend endTime = iff(properties.status =~ `"InProgress`" or properties.status =~ `"NotStarted`", datetime(null), todatetime(properties.lastModifiedDateTime))
        | project id, operationId = properties.assessmentActivityId, assessmentStatus = properties.status, updateOperation = `"Assessment`", operationType, startTime = properties.startDateTime, endTime, properties"

        # We want to execute this loop until $queryResults.assessmentStatus -ne "InProgress". If the assessmentStatus eq "Succeeded", we can move on.
        do
        {
            Write-Verbose "Polling for assessment completion."
            Start-Sleep -Seconds 30 # During the first iteration, it may take up to 30 seconds for the assessment to start and update in the Resource Graph
            $queryResults = Search-AzGraph -Query $assessmentQuery -Subscription $SubscriptionId
            Write-Verbose "Operation Id: $($queryResults.operationId) Status: $($queryResults.assessmentStatus)"
        } while ($queryResults.assessmentStatus -eq "InProgress")

        return $queryResults
    }
}

function Get-AUMCAssessmentPatches {
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
    $queryResults.properties
}

function Invoke-AUMCOneTimeDeployment {
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

    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/installPatches?api-version=2020-12-01" -Method POST -Payload ($deploymentPayload | ConvertTo-Json -Depth 10)
 
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
        do
        {
            Write-Verbose "Polling for deployment completion."
            Start-Sleep -Seconds 30 # During the first iteration, it may take up to 30 seconds for the update to start and update in the Resource Graph

            # Get the status of the deployment. We want to find the most recent deployment for the resource. This is the first record returned, which is part of the filter in the query itself.
            $queryResults = Search-AzGraph -Query $deploymentStatusQuery -Subscription $SubscriptionId
            Write-Verbose "Operation Id: $($queryResults.operationId) Status: $($queryResults.updateDeploymentStatus)"
        } while ($queryResults.updateDeploymentStatus -eq "InProgress")
        
        return $queryResults
    }
}

function Get-AUMCDeploymentActivities {
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
    $queryResults.properties
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
        return 1
    }
}

function Add-AUMCConfigurationAssignment {
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

    $restResult = Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.compute/virtualmachines/$VMName/providers/Microsoft.Maintenance/configurationAssignments/$($ConfigurationAssignmentName)?api-version=2021-09-01-preview" -Method PUT -Payload $ConfigurationAssignmentPayload

    if ($restResult.StatusCode -ne 202) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return 1
    }
}

function Get-AUMCVMUpdateSettings {
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
    [CmdletBinding(SupportsShouldProcess=$True)]
	param(
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
        [Parameter(Mandatory=$false)]
        [ValidateSet('Enabled', 'Disabled')]
        [string]$HotPatching
	)

    if ([String]::IsNullOrWhiteSpace($AssessmentMode) -and [String]::IsNullOrWhiteSpace($PatchMode) -and [String]::IsNullOrWhiteSpace($HotPatching)) {
        throw "At least one of AssessmentMode, PatchMode, or HotPatching must be set."
    }
    
    # Get the VM profile so we can create the appropriate payload
    $vmJson = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)?api-version=2022-11-01" -Method GET
    $vm = $vmJson.Content | ConvertFrom-Json

    # Go down each path for the osType
    if ($vm.properties.storageProfile.osDisk.osType -eq 'Linux') {
        if ($PatchMode -in @('AutomaticByOS','Manual')) {
            throw "$PatchMode patch orchestration is only available on Windows."
        }

        if ($null -ne $HotPatching) {
            throw "Hot patching's value is set, but is only available on Windows."
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
            $payLoad.properties.osProfile.windowsConfiguration.patchSettings["enableHotpatching"] = if ($HotPatching -eq 'Enabled') { $true } else { $false }
        }
    }

    # NOTE: We use the direct REST API command instead of Set-AzVMOperatingSystem so we don't need to pull a PSCredential object.
    $restResult = Invoke-AzRestMethod -Path "subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Compute/virtualMachines/$($VMName)?api-version=2022-11-01" -Method PUT -Payload ($payLoad | ConvertTo-Json -Depth 10)
    
    if ($restResult.StatusCode -ne 200) {
        $errorObj = ($restResult.Content | ConvertFrom-Json).error
        Write-Error -Message $errorObj.message -ErrorId $errorObj.code
        return $result.Content
    }

    return $restResult.Content
}

Export-ModuleMember -Function Add-AUMCConfigurationAssignment
Export-ModuleMember -Function Invoke-AUMCAssessment, Invoke-AUMCOneTimeDeployment
Export-ModuleMember -Function Get-AUMCAssessmentPatches, Get-AUMCDeploymentActivities, Get-AUMCDeploymentHistory, Get-AUMCVMUpdateSettings
Export-ModuleMember -Function Set-AUMCVMUpdateSettings
