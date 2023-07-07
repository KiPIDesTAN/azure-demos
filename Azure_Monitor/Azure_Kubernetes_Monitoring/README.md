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

Deploy the baseline resources
```pwsh
az deployment group create --name AKSMonitoring --resource-group <resource_group_name> --template-file aks_monitoring.bicep --parameters aks_monitoring.bicepparam
```

Set the Prometheus DCE network isolation via a separate deployment
```pwsh
az deployment group create --name AKSPrometheusMonitoring --resource-group 'MA_<resource_group_name>_<location>_managed' --template-file aks_monitoring_amw.bicep --parameters aks_monitoring_amw.bicepparam
```