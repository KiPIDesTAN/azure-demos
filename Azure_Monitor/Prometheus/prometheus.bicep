@description('appIdentifier is a unique identifier ')
param appIdentifier string
param vmAdminUsername string = 'azureuser'
param sshPublicKey string
param location string = resourceGroup().location
@description('Principal ID of the user who will be assigned Monitoring Data Reader writes on the Azure Monitor Workspace')
param principalId string 

// Define self-generated items
var amwName = 'amw-${appIdentifier}-${location}'    // Azure Monitor Workspace name
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
//var cloudInit = base64(loadTextContent('cloud-init.yml')) // Yaml file containing the cloud-init data

var amwRoleDefinitionId = 'b0d8363b-8ddd-447d-831f-62ca05bff136' // Role definition ID for Monitoring Data Reader used to query an Azure Monitor Workspace
var amwRoleAssignmentName = guid(principalId, amwRoleDefinitionId)  // Unique name for the role assignment resource


var sshInternalPort = 22  // port SSH runs on within the VM

// Create the Azure Monitor Workspace.
// When this resource is created, it will create a managed resource group for the Azure Monitor Workspace, which includes a default DCR and DCE. This DCR and DCE are intended for Prometheus remote writes.
resource amwAccount 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: amwName
  location: location
}

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
