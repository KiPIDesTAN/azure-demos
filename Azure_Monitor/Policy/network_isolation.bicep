targetScope = 'subscription'

var dceNetworkIsolationPolicyDefinitionName = 'policy-dce-network-isolation'
var lawNetworkIsolationPolicyDefinitionName = 'policy-law-network-isolation'
var amplsNetworkIsolationPolicyDefinitionName = 'policy-ampls-network-isolation'
var monitoringNewtorkIsolationPolicySet = 'policy-set-monitoring-network-isolation'

// Azure Policy to check the network isolation on Data Collection Endpoints is set appropriately.
resource dceNetworkIsolationPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: dceNetworkIsolationPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Data Collection Endpoint Network Isolation'
    description: 'Verifies the network isolation on a Data Collection Endpoints is set appropriately.'
    mode: 'All'
    metadata: {
      category: 'Monitoring'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: [
          'Audit'
          'Deny'
        ]
        metadata: {
          displayName: 'Effect'
          description: 'Audit or Deny the ability to create a Data Collection Endpoints with misconfigured network isolation.'
        }
      }
      publicNetworkAccess: {
        type: 'String'
        defaultValue: 'Disabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access'
          description: 'The public network access setting for the Data Collection Endpoint.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Insights/dataCollectionEndpoints'
          }
          {
            field: 'Microsoft.Insights/dataCollectionEndpoints/networkAcls.publicNetworkAccess'
            notEquals: '[parameters(\'publicNetworkAccess\')]'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Azure Policy to check the network isolation on a Log Analytics Workspace is set appropriately.
resource lawNetworkIsolationPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: lawNetworkIsolationPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Network Isolation'
    description: 'Verifies the network isolation on a Log Analytics Workspace is set appropriately.'
    mode: 'All'
    metadata: {
      category: 'Monitoring'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: [
          'Audit'
          'Deny'
        ]
        metadata: {
          displayName: 'Effect'
          description: 'Audit or Deny the ability to create a Log Analytics Workspace with misconfigured network isolation.'
        }
      }
      publicNetworkAccessForIngestion: {
        type: 'String'
        defaultValue: 'Disabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access for Ingestion'
          description: 'The public network access ingestion setting for the Log Analytics Workspace.'
        }
      }
      publicNetworkAccessForQuery: {
        type: 'String'
        defaultValue: 'Enabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access for Querying'
          description: 'The public network access querying setting for the Log Analytics Workspace.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.OperationalInsights/workspaces'
          }
          {
            anyOf: [
              {
                field: 'Microsoft.OperationalInsights/workspaces/publicNetworkAccessForIngestion'
                notEquals: '[parameters(\'publicNetworkAccessForIngestion\')]'
              }
              {
                field: 'Microsoft.OperationalInsights/workspaces/publicNetworkAccessForQuery'
                notEquals: '[parameters(\'publicNetworkAccessForQuery\')]'
              }
            ]
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Azure Policy to check the network isolation on a Log Analytics Workspace is set appropriately.
resource amplsNetworkIsolationPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: amplsNetworkIsolationPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Azure Monitor Private Link Scope Network Isolation'
    description: 'Verifies the network isolation on a Azure Monitor Private Link Scope is set appropriately.'
    mode: 'All'
    metadata: {
      category: 'Monitoring'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: [
          'Audit'
          'Deny'
        ]
        metadata: {
          displayName: 'Effect'
          description: 'Audit or Deny the ability to create an Azure Monitor Private Link Scope with misconfigured network isolation.'
        }
      }
      ingestionAccessMode: {
        type: 'String'
        defaultValue: 'PrivateOnly'
        allowedValues: [
          'Open'
          'PrivateOnly'
        ]
        metadata: {
          displayName: 'Public Network Access for Ingestion Access Mode'
          description: 'The public network access ingestion setting for the Azure Monitor Private Link Scope.'
        }
      }
      queryAccessMode: {
        type: 'String'
        defaultValue: 'PrivateOnly'
        allowedValues: [
          'Open'
          'PrivateOnly'
        ]
        metadata: {
          displayName: 'Public Network Access for Querying Access Mode'
          description: 'The public network access querying setting for the Azure Monitor Private Link Scope.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Insights/privateLinkScopes'
          }
          {
            anyOf: [
              {
                field: 'microsoft.insights/privateLinkScopes/accessModeSettings.ingestionAccessMode'
                notEquals: '[parameters(\'ingestionAccessMode\')]'
              }
              {
                field: 'microsoft.insights/privateLinkScopes/accessModeSettings.queryAccessMode'
                notEquals: '[parameters(\'queryAccessMode\')]'
              }
            ]
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Create the Policy Initiative for the policies above
resource newtorkIsolationPolicySet 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: monitoringNewtorkIsolationPolicySet
  properties: {
    policyType: 'Custom'
    displayName: 'Monitoring network isolation'
    description: 'Monitoring should be done with network isolation enabled.'
    metadata: {
      category: 'Monitoring'
      version: '1.0.0'
    }
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: [
          'Audit'
          'Deny'
        ]
        metadata: {
          displayName: 'Effect'
          description: 'Audit or Deny the ability to inappropriately set network isolation on Azure Monitor resources.'
        }
      }
      publicNetworkAccess: {
        type: 'String'
        defaultValue: 'Disabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access'
          description: 'The public network access setting for the Data Collection Endpoint.'
        }
      }
      publicNetworkAccessForIngestion: {
        type: 'String'
        defaultValue: 'Disabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access for Ingestion'
          description: 'The public network access ingestion setting for the Log Analytics Workspace.'
        }
      }
      publicNetworkAccessForQuery: {
        type: 'String'
        defaultValue: 'Enabled'
        allowedValues: [
          'Enabled'
          'Disabled'
        ]
        metadata: {
          displayName: 'Public Network Access for Querying'
          description: 'The public network access querying setting for the Log Analytics Workspace.'
        }
      }
      ingestionAccessMode: {
        type: 'String'
        defaultValue: 'PrivateOnly'
        allowedValues: [
          'Open'
          'PrivateOnly'
        ]
        metadata: {
          displayName: 'Public Network Access for Ingestion Access Mode'
          description: 'The public network access ingestion setting for the Azure Monitor Private Link Scope.'
        }
      }
      queryAccessMode: {
        type: 'String'
        defaultValue: 'PrivateOnly'
        allowedValues: [
          'Open'
          'PrivateOnly'
        ]
        metadata: {
          displayName: 'Public Network Access for Querying Access Mode'
          description: 'The public network access querying setting for the Azure Monitor Private Link Scope.'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: dceNetworkIsolationPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          publicNetworkAccess: { value: '[parameters(\'publicNetworkAccess\')]' }
        }
      }
      {
        policyDefinitionId: lawNetworkIsolationPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          publicNetworkAccessForIngestion: { value: '[parameters(\'publicNetworkAccessForIngestion\')]' }
          publicNetworkAccessForQuery: { value: '[parameters(\'publicNetworkAccessForQuery\')]' }
        }
      }
      {
        policyDefinitionId: amplsNetworkIsolationPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          ingestionAccessMode: { value: '[parameters(\'ingestionAccessMode\')]' }
          queryAccessMode: { value: '[parameters(\'queryAccessMode\')]' }
        }
      }
    ]
  }
}
