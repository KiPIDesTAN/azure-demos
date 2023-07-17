$resourceGroupName = 'rg-promtest2'
$nodeResourceGroupName = "MC_rg-promtest2_aks-aks-monitoring-eastus2"

az group create --location eastus2 --name $resourceGroupName

Deploy to the main resource group

az deployment group create --name AKSResources --resource-group $resourceGroupName --template-file 01_resources.bicep --parameters 01_resources.bicepparam

Deploy PE, private DNS to the AKS management group

az deployment group create --name AKSNodeResources --resource-group $nodeResourceGroupName --template-file 02_node_resources.bicep --parameters 02_node_resources.bicepparam


$aadIdentity = 'adam_adamnewhard.com#EXT#@adamnewhardgmail.onmicrosoft.com'
$resourceGroupName = 'rg-promtest2'
$aksClusterName = 'aks-aks-monitoring-eastus2'

# Get the resource ID of the AKS cluster
$AKS_ID=$(az aks show -g $resourceGroupName -n $aksClusterName --query id -o tsv)

# Assign yourself the AKS cluster admin role. This gives you super dooper user access to the cluster.
az role assignment create --role "Azure Kubernetes Service RBAC Cluster Admin" --assignee $aadIdentity --scope $AKS_ID