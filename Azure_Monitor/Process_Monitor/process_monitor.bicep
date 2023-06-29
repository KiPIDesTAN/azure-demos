param appIdentifier string
param vmAdminUsername string = 'azureuser'
param sshPublicKey string
param location string = resourceGroup().location

// Define self-generated items
var dcrName = 'dcr-${appIdentifier}-${location}-process-monitor' // Data collection rule name
var dceName = 'dce-${appIdentifier}-${location}-process-monitor'  // Data collection endpoint name
var lawName = 'law-${appIdentifier}-${location}'    // Log Analytics Workspace name
var nsgName = 'nsg-${appIdentifier}-${location}'   // NSG Name
var vnetName = 'vnet-${appIdentifier}-${location}' // Vnet name
var vnetSubnetName = 'vnet-${appIdentifier}-${location}-subnet' // Vnet subnet name
var vmName = 'vm-${appIdentifier}-${location}'        // VM name
var vmNicName = '${vmName}-nic' // VM NIC name
var vmPublicIPName = '${vmName}-pip' // VM Public IP name
var vmOSDiskName = '${vmName}-os-${uniqueString(vmName)}' // VM OS Disk name
var cloudInit = base64(loadTextContent('cloud-init.yml')) // Yaml file containing the cloud-init data

var sshInternalPort = 22  // port SSH runs on within the VM

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

// Create the Process Monitor custom table. The column names are based on the output from the process_monitor.sh script.
// The output columns from the ps command are not human-readable. The columns below are the human-readable representation
// of those columns. This information can be gathered by looking at the ps manpage.
resource lawTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  name: 'ProcessMonitor_CL'
  parent: law
  properties: {
    schema: {
      columns: [
        {
          name: 'TimeGenerated'
          type: 'datetime'
        }
        {
          name: 'ProcessId'
          type: 'int'
        }
        {
          name: 'UserId'
          type: 'int'
        }
        {
          name: 'ParentProcessId'
          type: 'int'
        }
        {
          name: 'CpuUtilization'
          type: 'int'
        }
        {
          name: 'StartTime'
          type: 'string'
        }
        {
          name: 'Tty'
          type: 'string'
        }
        {
          name: 'CpuTime'
          type: 'string'
        }
        {
          name: 'Cmd'
          type: 'string'
        }
      ]
      name: 'ProcessMonitor_CL'
    }
  }
}

// Create the data collection end point that is required by the custom text log data collection rule.
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2021-09-01-preview' = {
  name: dceName
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Create the data collection rule to send the data to the workspace.
// The data flow's transformKql is paramount to parsing the incoming log line into the discrete fields within the
// custom table target, denoted by outputStream.
resource dcr 'Microsoft.Insights/dataCollectionRules@2021-09-01-preview' = {
  name: dcrName
  location: location
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-ProcessMonitor': {
        columns: [
            {
                name: 'TimeGenerated'
                type: 'datetime'
            }
            {
                name: 'RawData'
                type: 'string'
            }
        ]
      }
    }
    dataSources: {
      logFiles: [
        {
          name: 'Custom-ProcessMonitor'
          streams: [ 'Custom-ProcessMonitor' ]
          filePatterns: [ '/var/log/process_monitor/*.log' ]
          format: 'text'
          settings: {
            text: {
              recordStartTimestampFormat: 'ISO 8601'
            }
          }
          
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'lawWorkspace'
          workspaceResourceId: law.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-ProcessMonitor' ]
        destinations: [ 'lawWorkspace' ]
        outputStream: 'Custom-ProcessMonitor_CL'
        transformKql: 'source | parse RawData with TimeGenerated:datetime ", " ProcessId:int "," UserId:int "," ParentProcessId:int "," CpuUtilization:int "," StartTime "," Tty "," CpuTime "," Cmd'
      }
    ]
  }
  dependsOn: [
    lawTable
  ]
}

// Spin up the virtual machine with cloud-init configuration
// NSG
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '${sshInternalPort}'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    dhcpOptions: {
      dnsServers: []
    }
    subnets: [
      {
        name: vnetSubnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateLinkServiceNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource vmPublicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: vmPublicIPName
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'

  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2022-07-01' = {
  name: vmNicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, vnetSubnetName)
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
          publicIPAddress: {
            id: vmPublicIp.id
          }
        }
      }
    ]
    enableAcceleratedNetworking: true
    nicType: 'Standard'
  }
  dependsOn: [
    vnet
  ]
}

resource vm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: vmOSDiskName
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Delete'
        diskSizeGB: 30
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      customData: cloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
        enableVMAgentPlatformUpdates: false
      }
      allowExtensionOperations: true
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
  }
}

resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2022-11-01' = {
  name: 'AzureMonitorLinuxAgent'
  location: location
  parent: vm
  properties: {
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.24'
  }
}

// Associate the VM with the Data Collection Rule
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2021-09-01-preview' = {
  name: '${dcrName}-a'
  scope: vm
  properties: {
    dataCollectionRuleId: dcr.id
  }
}
