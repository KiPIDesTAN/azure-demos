# Azure Policy

This folder contains demos for various Azure Policies related to monitoring. These policies do not execute policy assignments. They only create policies and initiatives. See below for a list of the implemented policies.

- [Deployment](#deployment)
- [Log Analytics Workspace - Table Retention](#log-analytics-workspace---table-retention)
  - [Demo Files](#demo-files)
- [Log Analytics Workspace - Targeted - Table Retention](#log-analytics-workspace---targeted---table-retention)
  - [Demo Files](#demo-files-1)
- [Log Ingestion API - Prevent Populating Microsoft Table](#log-ingestion-api---prevent-populating-microsoft-table)
  - [Demo Files](#demo-files-2)
- [Network Isolation](#network-isolation)
  - [Demo Files](#demo-files-3)


## Deployment

The commands below will deploy the policy files. They are written for PowerShell syntax. Changing them to bash should be straight forward. The commands below assume your az cli is already logged into the right account and the subscription is set appropriately.

If you are deploying at the subscription, use the command below.

__NOTE:__ A parameter file may not always be required.

```pwsh
az deployment sub create --location <location> --template-file <filname.bicep> --parameters <parameter-file.bicepparam>
```

## Log Analytics Workspace - Table Retention

This policy will check for the retention time period set across all tables in a Log Analytics Workspace. If the retention period, for actively queriable data, is beyond a set retention period, the policy will fail.

There are two policies within the policy initiative.

1. Triggers off the Log Analytics Workspace setting a default retention period.
2. Triggers off an individual table within a Log Analytics Workspace, checking the individual table.

The default retention check is 30 days.

This policy initiative does not check the total retention. Total retention is not often something people care about.

### Demo Files

- [log_analytics_table_retention.bicep](./log_analytics_table_retention.bicep)

## Log Analytics Workspace - Targeted - Table Retention

This policy will check to make sure specific tables have their retention period set appropriately. If the retention period does not match the desired value, the policy will fail.

For example, you can use this policy to make sure the InsightsMetrics Log Analytics Workspace table has a retention of 60 days. 

__NOTE:__ If this policy exists and looks for table X to have a retention date Y, deploying a Log Analytics Workspace with a default table retention period of Z has unique results. When the policy effect is set to deny, the Log Analytics Workspace will not fail and the table that requires retention date Y will successfully be created with retention period Z. The policy will only deny a change if someone changes the table's retention period to something other than Y. The non-compliant table will appear in the compliant list after the Policy runs on its normal schedule.

When the policy effect is set to audit, the Log Analytics Workspace deployment will not fail and the table that requires retention date Y will successfully be created with retention period Z. The non-compliant table will appear in the compliant list after the Policy runs on its normal schedule.

### Demo Files

- [log_analytics_targeted_table_retention.bicep](./log_analytics_targeted_table_retention.bicep)

## Log Ingestion API - Prevent Populating Microsoft Table

This policy will block the use of the Log Ingestion API from populating a Microsoft-delivered table. The policy works by auditing for or preventing the deployment of a Data Collection Rule that has a data flow where at least one stream does not start with "Microsoft-", but the output stream contains "Microsoft-".

### Demo Files

- [log_ingestion_api.bicep](./log_ingestion_api.bicep)

## Network Isolation

Network isolation allows you to check the appropriate network isolation for monitoring related resources. This policy would best be used to force network isolation on monitoring resources, such as Azure Monitor Private Link Scopes, Log Analytics Workspaces, and Data Collection Endpoints. This policy can be used to prevent teams from sending monitoring traffic over the public Internet and instead force the traffic onto the Azure backbone.

The following items are checked by the Azure Policy Initiative with their default values.

| Resource Type | Check | Default Value |
|---|---|---|
| Data Collection Endpoint | Public Network Access | Disabled |
| Log Analytics Workspace | Public Network - Ingestion</br>Public Network - Query | Ingestion - Disabled</br>Query - Enabled |
| Azure Monitor Private Link Scope | Public Network - Ingestion</br>Public Network - Query  | Ingestion - PrivateOnly</br>Query - PrivateOnly |

The Log Analytics Workspace has its public network access for querying set to enabled by default so traffic originating outside a vnet can query the Log Analytics Workspace. In other words, a remote worker using their home internet, not through a VPN, can query data in a Log Analytics Workspace.

### Demo Files

- [network_isolation.bicep](./network_isolation.bicep)
