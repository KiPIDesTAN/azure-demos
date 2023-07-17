# Azure Kubernetes Monitoring

This area contains information about spinning up an AKS cluster and monitoring it with Container Insights and Managed Prometheus. The primary purpose is to document the bicep commands to associate the appropriate functionality with the AKS instance.

The bicep file will do the following:

1. Create a Log Analytics Workspace
2. Deploy the AKS cluster with the omsagent add-on to support Container Insights and enabling the Azure Monitor profile for Managed Prometheus


## Deployment

Login to Azure

```pwsh
az login
```

Set the correct subscription for the deployment

```pwsh
az account set --subscription <subscription_id>
```

Create the resource group

```pwsh
az group create --location <location> --name <resource_group_name>
```

Deploy the initial code

```pwsh
az deployment group create --name AKSMonitoring --resource-group <resource_group_name> --template-file aks_monitoring.bicep --parameters aks_monitoring.bicepparam
```

Modify the Prometheus created DCE to set network isolation to private. See the [note](#prometheus-deployment-note) below.

```pwsh
az deployment group create --name AKSPrometheus --resource-group MA_amw-<appIdentifier>-<location>_<location>_managed --template-file aks_monitoring_amw.bicep --parameters aks_monitoring_amw.bicepparam
```

## Access AKS with Kubectl

This deployment uses Azure RBAC for authentication. If you need to access the cluster from kubectl, run the following commands after running az login. You are the Owner of the AKS cluster, which allows you to add yourself as an admin within the cluster.

Install kubectrl if it's not already there.

```pwsh
$aadIdentity = '<aad-identity>'
$resourceGroupName = '<resource-group-name>'
$aksClusterName = '<aks-cluster-name>'

# Get the resource ID of the AKS cluster
$AKS_ID=$(az aks show -g $resourceGroupName -n $aksClusterName --query id -o tsv)

# Assign yourself the AKS cluster admin role. This gives you super dooper user access to the cluster.
az role assignment create --role "Azure Kubernetes Service RBAC Cluster Admin" --assignee $aadIdentity --scope $AKS_ID
```



## Prometheus Deployment Note

When Managed Prometheus is deployed, it auto-created a resource group of the format 'MA\_&lt;monitor-workspace-name>\_&lt;location>\_managed'. As part of the aks_monitoring.bicep deployment, we create an Azure Monitor Workspace named 'amw-&lt;appIdentifier>-&lt;location>'. appIdentifier comes from the bicepparam file. The location can be set within the bicepparam file as well, but is defaulted to the resource group's location. Thus, the final calculated resource group name is 'MA\_amw-&lt;appIdentifier>-&lt;location>\_&lt;location>\_managed'.

For more information on why there is a second deployment step, please, see my documentation on AKS Monitoring in the [deployment - Managed Prometheus](https://kipidestan.github.io/Azure-AKS-Observability-Options/#deployment---managed-prometheus) section.