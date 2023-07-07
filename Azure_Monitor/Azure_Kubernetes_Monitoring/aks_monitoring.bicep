param appIdentifier string
param location string = resourceGroup().location
param kubernetesVersion string = '1.25.6'
param aksEnableRBAC bool = true
@allowed([
  'kubenet'
  'azure'
])
param aksNetworkPlugin string = 'kubenet'

// Define self-generated items
var lawName = 'law-${appIdentifier}-${location}'    // Log Analytics Workspace name
var amplsName = 'ampls-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name
var amplsScopeLawName = 'amplsScopeLaw-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name for Log Analytics Workspace
var amplsScopeAmwDceName = 'amplsScopeAmwDceName-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name for Managed Prometheus
var amplsScopeCiDceName = 'amplsScopeCiDceName-${appIdentifier}-${location}'    // Azure Monitor Private Link Scope name for Container Insights
var amwName = 'amw-${appIdentifier}-${location}'    // Azure Monitor Workspace name
var amwManagedRgName = 'MA_${amwName}_${location}_managed' // Azure Monitor Workspace managed resource group name
var aksName = 'aks-${appIdentifier}-${location}'    // AKS Cluster name
var aksDnsPrefix = '${aksName}-dns'               // AKS DNS prefix
var aksNodeResourceGroup = 'MC_${resourceGroup().name}_${aksName}' // AKS Node resource group name
var dcrCIName = 'MSCI-${appIdentifier}-${location}' // Data collection rule name for Container Insights
var dceCIName = 'dce-CI-${appIdentifier}-${location}'  // Data collection endpoint name Container Insights uses

// Create the Log Analytics workspace.
resource law 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: lawName
  location: location
  properties: {
    publicNetworkAccessForIngestion: 'Enable'
    publicNetworkAccessForQuery: 'Enable'
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Create the DCE for Container Insights
resource dceCI 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dceCIName
  location: location
  properties: {
    description: 'Data collection endpoint used by Container Insights'
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

// Create the Azure Monitor Workspace.
// When this resource is created, it will create a managed resource group for the Azure Monitor Workspace, which includes a DCR and DCE.
resource amwAccount 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: amwName
  location: location
}

// Create the AMPLS
resource ampls 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
  name: amplsName
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'Open'
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

// Link the LAW to the AMPLS
resource amplsScopeCiDce 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: amplsScopeCiDceName
  parent: ampls
  properties: {
    linkedResourceId: dceCI.id
  }
}

// Create the AKS instance withe support for Container Insights and Managed Prometheus
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


// Create DCR for Container Insights and SysLog.
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
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
        streams: [ 'Microsoft-ContainerInsights-Group-Default' ]
        destinations: [ 'logAnalyticsDestination' ]
      }
    ]
  }
}

// Create the DCE association of the CI to the AKS cluster
resource dcraDceCI 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: 'configurationAccessEndpoint'
  scope: aks
  properties: {
    dataCollectionEndpointId: dceCI.id
  }
}

// Create the DCR association of the CI to the AKS cluster
resource dcraCI 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${dcrCIName}-a'
  scope: aks
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the Container Insights data collection for this AKS Cluster.'
    dataCollectionRuleId: dcr.id
  }
}

// Link the Azure Monitor Workspace DCE to the AMPLS
resource amplsScopeAmwDCE 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  name: amplsScopeAmwDceName
  parent: ampls
  properties: {
    linkedResourceId: amwAccount.properties.defaultIngestionSettings.dataCollectionEndpointResourceId
  }
}

// Create the DCR association for Azure Monitor Workspace to the AKS cluster
resource dcraAMW 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${amwName}-a'
  scope: aks
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the Prometheus Metrics data collection for this AKS Cluster.'
    dataCollectionRuleId: amwAccount.properties.defaultIngestionSettings.dataCollectionRuleResourceId
  }
}


