# Azure Policy

This folder contains demos for various Azure Policies related to monitoring. These policies do not execute policy assignments. They only create policies and initiatives. See below for a list of the implemented policies.

## Deployment

The commands below will deploy the policy files. They are written for PowerShell syntax. Changing them to bash should be straight forward. The commands below assume your az cli is already logged into the right account and the subscription is set appropriately.

If you are deploying at the subscription, use the command below.

__NOTE:__ A parameter file may not always be required.

```pwsh
az deployment sub create --location <location> --template-file <filname.bicep> --parameters <parameter-file.bicepparam>
```

If you are deploying at the management level, open the bicep file, change the targetScope from

```bicep
targetScope = 'subscription'
```

to 

```bicep
targetScope = 'managementGroup'
```

Then, run the appropriate az deployment command for management groups, such as the command below.

__NOTE:__ A parameter file may not always be required.

```pwsh
az deployment mg create --location <location> --management-group-id --template-file <filname.bicep> --parameters <parameter-file.bicepparam>
```
## Log Analytics Workspace - Table Retention

This policy will check for the retention time period set across all tables in a Log Analytics Workspace. If the retention period, for actively queriable data, is beyond a set retention period, the policy will fail.

There are two policies within the policy initiative.

1. Triggers off the Log Analytics Workspace setting a default retention period.
2. Triggers off an individual table within a Log Analytics Workspace, checking the individual table.

The default retention check is 30 days.

This policy initiative does not check the total retention. Total retention is not often something people care about.

## Network Isolation

Network isolation allows you to check the appropriate network isolation for monitoring related resources. This policy would best be used to force network isolation on monitoring resources, such as Azure Monitor Private Link Scopes, Log Analytics Workspaces, and Data Collection Endpoints. This policy can be used to prevent teams from sending monitoring traffic over the public Internet and instead force the traffic onto the Azure backbone.

The following items are checked by the Azure Policy Initiative with their default values.

| Resource Type | Check | Default Value |
|---|---|---|
| Data Collection Endpoint | Public Network Access | Disabled |
| Log Analytics Workspace | Public Network - Ingestion</br>Public Network - Query | Ingestion - Disabled</br>Query - Enabled |
| Azure Monitor Private Link Scope | Public Network - Ingestion</br>Public Network - Query  | Ingestion - PrivateOnly</br>Query - PrivateOnly |

The Log Analytics Workspace has its public network access for querying set to enabled by default so traffic originating outside a vnet can query the Log Analytics Workspace. In other words, a remote worker using their home internet, not through a VPN, can query data in a Log Analytics Workspace.

