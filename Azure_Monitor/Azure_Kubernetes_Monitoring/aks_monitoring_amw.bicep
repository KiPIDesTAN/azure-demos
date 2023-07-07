param appIdentifier string
param location string = resourceGroup().location

var amwName = 'amw-${appIdentifier}-${location}'    // Azure Monitor Workspace name

// When an Azure Monitor Workspace is created, a default management group is created with a DCR and DCE of the same name as the Azure Monitor Workspace.
// This code acquires those resources and returns them to the calling module.

// Get the DCE used by Azure Monitor Workspace and disabled
resource dceAMW 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: amwName
  location: location
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}
