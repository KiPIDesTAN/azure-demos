// This file gets run second. It sets up all the private DNS zones for AMPLS
@description('Location where all the resources will be deployed. Defaults to the resource group location.')
param location string = resourceGroup().location
@description('Name of the vnet where the AKS VMSS nodes exist.')
param vnetName string
@description('Resource ID of the AMPLS the private endpoint will link to')
param amplsId string

// Load shared variables
var sharedVars = loadJsonContent('./shared_variables.json')
var appIdentifier = sharedVars.appIdentifier

// Variables
var amplsPEName = 'pe-${appIdentifier}-${location}-ampls' // PE pointing to the AMPLS in the pe subnet vnet

// Create the Azure Monitor Private DNS Zones

// Get the vnet that should be associated with the private DNS zones
resource vnet 'Microsoft.Network/virtualNetworks@2020-06-01' existing = {
  name: vnetName
}

// Create a private endpoint within the VNet to connect to the AMPLS
// AMPLS private endpoint
resource amplsPE 'Microsoft.Network/privateEndpoints@2022-07-01' = {
  name: amplsPEName
  location: location
  properties: {
    customNetworkInterfaceName: '${amplsPEName}-nic'
    privateLinkServiceConnections: [
      {
        name: amplsPEName
        properties: {
          privateLinkServiceId: amplsId
          groupIds: [
            'azuremonitor'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
            actionsRequired: 'None'
          }
        }
      }
    ]
    subnet: {
      id: vnet.properties.subnets[0].id     // Put the PE in the first subnet. This may be an area where someone wants to do some better management of their PE location.
    }
  }
}


// AMPLS private dns zones
resource agentsvcPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.agentsvc.azure-automation.net'
  location: 'global'
}

resource agentsvcPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: agentsvcPrivateDnsZone
  name: 'privatelink.agentsvc.azure-automation.net-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource blobCorePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource blobCorePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: blobCorePrivateDnsZone
  name: 'privatelink.blob.${environment().suffixes.storage}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource monitorPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.monitor.azure.com'
  location: 'global'
}

resource monitorPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: monitorPrivateDnsZone
  name: 'privatelink.monitor.azure.com-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource odsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
}

resource odsPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: odsPrivateDnsZone
  name: 'privatelink.ods.opinsights.azure.com-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource omsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.oms.opinsights.azure.com'
  location: 'global'
}

resource omsPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: omsPrivateDnsZone
  name: 'privatelink.oms.opinsights.azure.com-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource pvtEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: 'default'
  parent: amplsPE
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'agentSvc'
        properties: {
          privateDnsZoneId: agentsvcPrivateDnsZone.id
        }
      }
      {
        name: 'blobCore'
        properties: {
          privateDnsZoneId: blobCorePrivateDnsZone.id
        }
      }
      {
        name: 'monitor'
        properties: {
          privateDnsZoneId: monitorPrivateDnsZone.id
        }
      }
      {
        name: 'ods'
        properties: {
          privateDnsZoneId: odsPrivateDnsZone.id
        }
      }
      {
        name: 'oms'
        properties: {
          privateDnsZoneId: omsPrivateDnsZone.id
        }
      }
    ]
  }
}
