@description('Location where all the resources will be deployed. Defaults to the resource group location.')
param location string = resourceGroup().location
@description('Kubernetes version. Defaults to 1.25.6.')
param kubernetesVersion string = '1.25.6'
@description('Enabled RBAC on the AKS cluster. Defaults to true.')
param aksEnableRBAC bool = true
@description('AKS networking type. Defaults to kubenet.')
@allowed([
  'kubenet'
  'azure'
])
param aksNetworkPlugin string = 'kubenet'
@description('Principal ID of the user who will be assigned Monitoring Data Reader writes on the Azure Monitor Workspace')
param principalId string 

// Load shared variables
var sharedVars = loadJsonContent('./shared_variables.json')
var appIdentifier = sharedVars.appIdentifier

// Define self-generated items
var lawName = 'law-${appIdentifier}-${location}'    // Log Analytics Workspace name
var amplsName = 'ampls-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name
var amplsScopeLawName = 'amplsScopeLaw-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name for Log Analytics Workspace
var amplsScopeDceName = 'amplsScopeDceName-${appIdentifier}-${location}'    // Data Collection Endpoint used by AKS to get its configuration for both Container Insights and Managed Prometheus
var amplsScopePromDceName = 'amplsScopePromDceName-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name for Managed Prometheus
var amwName = 'amw-${appIdentifier}-${location}'    // Azure Monitor Workspace name
var aksName = 'aks-${appIdentifier}-${location}'    // AKS Cluster name
var aksDnsPrefix = '${aksName}-dns'               // AKS DNS prefix
var aksNodeResourceGroup = 'MC_${resourceGroup().name}_${aksName}' // AKS Node resource group name
var dcrCIName = 'MSCI-${appIdentifier}-${location}' // Data collection rule name for Container Insights
var dceName = 'MSCI-${appIdentifier}-${location}'  // Data collection endpoint name Container Insights uses
var dcrPROMName = 'MSProm-${appIdentifier}-${location}' // Data collection rule name for Managed Prometheus
var dcePROMName = 'MSProm-${appIdentifier}-${location}'  // Data collection endpoint name Managed Prometheus uses

var amwRoleDefinitionId = 'b0d8363b-8ddd-447d-831f-62ca05bff136' // Role definition ID for Monitoring Data Reader used to query an Azure Monitor Workspace
var amwRoleAssignmentName = guid(principalId, amwRoleDefinitionId)  // Unique name for the role assignment resource

// SECTION Base Infrastructure

// Create the AKS instance with support for Container Insights and Managed Prometheus
resource aks 'Microsoft.ContainerService/managedClusters@2023-04-01' = {
  name: aksName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    enableRBAC: aksEnableRBAC
    dnsPrefix: aksDnsPrefix
    nodeResourceGroup: aksNodeResourceGroup
    agentPoolProfiles: [
      {
        name: 'agentpool'
        osDiskSizeGB: 30
        count: 1
        enableAutoScaling: true
        minCount: 1
        maxCount: 1
        vmSize: 'Standard_B4ms'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        maxPods: 110
      }
    ]
    networkProfile: {
      loadBalancerSku: 'Standard'
      networkPlugin: aksNetworkPlugin
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: law.id
          useAADAuth: 'true'
        }
      }
    }
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
  }
}

// Create the Log Analytics workspace.
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  properties: {
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Enabled'
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Link the LAW to the AMPLS
resource amplsScopeLaw 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: amplsScopeLawName
  parent: ampls
  properties: {
    linkedResourceId: law.id
  }
}

// Create the Azure Monitor Private Link Scope for the Log Analytics Workspace
resource ampls 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: amplsName
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// !SECTION Base Infrastructure

// SECTION Container Insights

// Create DCR for Container Insights and SysLog.
resource dcrCI 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrCIName
  location: location
  properties: {
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: [ 'Microsoft-ContainerInsights-Group-Default' ]
          extensionSettings: {
            dataCollectionSettings: {
              interval: 'PT1M'
              namespaceFilteringMode: 'Off'
              namespaces: [
                'kube-system'
              ]
            }
          }
        }
      ]
      syslog: [
        {
          name: 'sysLogsDataSource'
          streams: [ 'Microsoft-Syslog' ]
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'mark'
            'kern'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
            'lpr'
            'mail'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Debug'
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
    }
    destinations:{
      logAnalytics: [
        {
          name: 'logAnalyticsDestination'
          workspaceResourceId: law.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-ContainerInsights-Group-Default', 'Microsoft-Syslog' ]
        destinations: [ 'logAnalyticsDestination' ]
      }
    ]
  }
}


// Create the DCE for Container Insights that will be associated with the AMPLS
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dceName
  location: location
  properties: {
    description: 'Data collection endpoint used by Container Insights'
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

// Link the Container Insights DCE to the AMPLS
resource amplsScopeDce 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: amplsScopeDceName
  parent: ampls
  properties: {
    linkedResourceId: dce.id
  }
}

// Create the DCR association of the CI to the AKS cluster
resource dcraCI 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${dcrCIName}-a'
  scope: aks
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the Container Insights data collection for this AKS Cluster.'
    dataCollectionRuleId: dcrCI.id
  }
}

// Create the DCE association of the CI to the AKS cluster
resource dcraDceCI 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'configurationAccessEndpoint'
  scope: aks
  properties: {
    dataCollectionEndpointId: dce.id
  }
}

// !SECTION Container Insights

// SECTION Prometheus

// Create the Azure Monitor Workspace.
// When this resource is created, it will create a managed resource group for the Azure Monitor Workspace, which includes a default DCR and DCE. This DCR and DCE are intended for Prometheus remote writes.
resource amwAccount 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: amwName
  location: location
}

// Create the DCE for Managed Prometheus
// NOTE: We are going to use this DCE for two purposes. One is the DCE required by the Prometheus DCR. The other is to force network isolation when AKS sends metrics through the AMPLS to AMW.
resource dcePROM 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dcePROMName
  location: location
  properties: {
    description: 'Data collection endpoint used by Managed Prometheus'
    networkAcls: {
      publicNetworkAccess: 'Disabled'  // TODO This should probably be disabled once we get it working
    }
  }
}

// Create the Prometheus DCR
resource dcrPROM 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrPROMName
  location: location
  properties: {
    dataCollectionEndpointId: dcePROM.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [ 'Microsoft-PrometheusMetrics' ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: amwAccount.id
          name: 'MonitoringAccount'
        }
      ]
    }
    dataFlows: [
      {
        destinations: [ 'MonitoringAccount' ]
        streams: [ 'Microsoft-PrometheusMetrics' ]
      }
    ]
  }
}

// Create the DCR association for Azure Monitor Workspace to the AKS cluster
resource dcraAMW 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'ContainerInsightsMetricsExtension'
  scope: aks
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the Prometheus Metrics data collection for this AKS Cluster.'
    dataCollectionRuleId: dcrPROM.id
  }
}

// Link the Managed Prometheus DCE to the AMPLS
resource amplsScopePromDce 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: amplsScopePromDceName
  parent: ampls
  properties: {
    linkedResourceId: dcePROM.id
  }
}

// !SECTION Prometheus

// SECTION Role Assignments

// Assign the use to the Monitoring Data Reader role on the AMW
resource amwRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: amwRoleAssignmentName
  scope: amwAccount
  properties: {
    principalId: principalId
    roleDefinitionId: tenantResourceId('Microsoft.Authorization/roleDefinitions', amwRoleDefinitionId)
  }
}

// !SECTION Role Assignments
