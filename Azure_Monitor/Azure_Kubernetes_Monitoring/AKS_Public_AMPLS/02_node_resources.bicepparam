using './02_node_resources.bicep'

param vnetName = '<aks-vnet-name>'    // Name of the vnet in the AKS managed node resource group
param amplsId = '<amplid-resource-id>'  // Resource ID of the Azure Monitor Private Link Scope
