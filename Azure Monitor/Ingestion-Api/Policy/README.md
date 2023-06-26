# Ingestion API Policy

In the event you want to block users from leveraging the Ingestion API, you can apply a policy that blocks adding an identity to the Metric Publisher role in the data collection rule. This demo will provide such a policy.

The policy looks for service principals assigned to the Monitoring Metrics Publisher role where the scope is on a data collection rule. __NOTE__ that there can be overlap with other services that require the Monitoring Metrics Publisher permission and you could inadvertently block that functionality. This specifically could happen with [custom metrics](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/metrics-custom-overview) that leverage a DCR. It is not a common practice that custom metrics leverage DCRs, but Azure frequently changes. Please, do your own research and testing before deploying this policy.

### Deploy

The following command can be run to deploy the policy with the az cli via PowerShell. If deploying in bash, replace the ` character with a \ to accomodate the multi-line command properly.

```pwsh
az policy definition create --name BlockIngestionApi --rules @ingestion-api.policy.json --params @ingestion-api.policy.params.json `
    --mode All `
    --display-name "Prevent role assignment to Monitoring Metric Publisher on data collection rules" `
    --description "This policy prevents the assignment of the Metric Publisher role on data collection rules." `
    --metadata "category=Monitoring,version=1.0.0"
```

Once the deployment completes, you will have the policy definition available. Per best practices, this policy should be associated with a new or existing Azure Policy Initiative. Assignments can then be made and the Effect parameter be set to indicate the desired effect that will occur on violations.