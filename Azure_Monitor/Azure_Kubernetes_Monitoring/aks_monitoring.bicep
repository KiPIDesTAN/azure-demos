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
var amwName = 'amw-${appIdentifier}-${location}'    // Azure Monitor Workspace name
var aksName = 'aks-${appIdentifier}-${location}'    // AKS Cluster name
var aksDnsPrefix = '${aksName}-dns'               // AKS DNS prefix
var aksNodeResourceGroup = 'MC_${resourceGroup().name}_${aksName}' // AKS Node resource group name
var dcrName = 'MSCI-${appIdentifier}-${location}' // Data collection rule name for Container Insights
var dceName = 'MSProm-${appIdentifier}-${location}' // Data collection endpoint name for Managed Prometheus

var nsgName = 'nsg-${appIdentifier}-${location}'   // NSG Name
var vnetName = 'vnet-${appIdentifier}-${location}' // Vnet name
var vnetSubnetName = 'vnet-${appIdentifier}-${location}-subnet' // Vnet subnet name

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

// Create the Azure Monitor Workspace.
resource amwAccount 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: amwName
  location: location
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

// Create the DCE used by Prometheus
// resource dce 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
//   name: dceName
//   location: location
//   kind: 'Linux'
// }

// Create DCR for Container Insights and SysLog.
resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  properties: {
    //dataCollectionEndpointId: dce.id  // DCE used by Prometheus. It is not used by CI.
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
      // prometheusForwarder: [
      //   {
      //     name: 'prometheusForwarderDataSource'
      //     streams: [ 'Microsoft-PrometheusMetrics' ]
      //     labelIncludeFilter: {} 
      //   }
      // ]
    }
    destinations:{
      logAnalytics: [
        {
          name: 'logAnalyticsDestination'
          workspaceResourceId: law.id
        }
      ]
      // monitoringAccounts: [
      //   {
      //     name: 'monitoringAccountsDestination'
      //     accountResourceId: amwAccount.id
      //   }
      // ]
    }
    dataFlows: [
      {
        streams: [ 'Microsoft-ContainerInsights-Group-Default' ]
        destinations: [ 'logAnalyticsDestination' ]
      }
      // {
      //   streams: [ 'Microsoft-PrometheusMetrics' ]
      //   destinations: [ 'monitoringAccountsDestination' ]
      // }
    ]
  }
}

// Create the DCR association
resource dcra 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = {
  name: '${dcrName}-a'
  scope: aks
  properties: {
    description: 'Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster.'
    dataCollectionRuleId: dcr.id
  }
}
