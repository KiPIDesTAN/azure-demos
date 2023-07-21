targetScope = 'subscription'

var lawRetentionPolicyDefinitionName = 'policy-definition-law-retention'
var lawTableRetentionPolicyDefinitionName = 'policy-definition-law-table-retention'
var lawTableRetentionPolicySetName = 'policy-set-law-table-retention'

// Create an Azure Policy for the default retention policy on the Log Analytics Workspace
resource lawRetentionPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: lawRetentionPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Default Table Retention'
    description: 'Verifies the Log Analytics Workspace default table retention period is set appropriately.'
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
      retentionInDays: {
        type: 'Integer'
        defaultValue: 30
        metadata: {
          displayName: 'Retention In Days'
          description: 'The maximum number of days of retention for a table.'
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
            field: 'Microsoft.OperationalInsights/workspaces/retentionInDays'
            greater: '[parameters(\'retentionInDays\')]'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}


// Create an Azure Policy for each individual table in a Log Analytics Workspace
resource lawTableRetentionPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: lawTableRetentionPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Table Retention'
    description: 'Verifies all tables within a Log Analytics Workspace have their retention period appropriately.'
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
      retentionInDays: {
        type: 'Integer'
        defaultValue: 30
        metadata: {
          displayName: 'Retention In Days'
          description: 'The maximum number of days of retention for a table.'
        }
      }
      ignoreTables: {
        type: 'Array'
        defaultValue: [ 'AzureActivity', 'AppAvailabilityResults', 'AppBrowserTimings', 'AppDependencies', 'AppEvents', 'AppExceptions', 'AppMetrics', 'AppPageViews', 'AppPerformanceCounters', 'AppRequests', 'AppSystemEvents', 'AppTraces', 'Usage' ]
        metadata: {
          displayName: 'Tables to ignore'
          description: 'A list of the tables to ignore as part of the policy.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.OperationalInsights/workspaces/tables'
          }
          {
            field: 'Microsoft.OperationalInsights/workspaces/tables/retentionInDays'
            greater: '[parameters(\'retentionInDays\')]'
          }
          {
            field: 'Microsoft.OperationalInsights/workspaces/tables/schema.name'
            notIn: '[parameters(\'ignoreTables\')]'
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
resource lawTableRetentionPolicySet 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: lawTableRetentionPolicySetName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Retention Policy Set'
    description: 'Log Analytics Workspace should have table retention policies less than a specific value.'
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
          description: 'Audit or Deny the ability to inappropriately set retention policies.'
        }
      }
      retentionInDays: {
        type: 'Integer'
        defaultValue: 30
        metadata: {
          displayName: 'Retention In Days'
          description: 'The maximum number of days of retention for a table.'
        }
      }
      ignoreTables: {
        type: 'Array'
        defaultValue: [ 'AzureActivity', 'AppAvailabilityResults', 'AppBrowserTimings', 'AppDependencies', 'AppEvents', 'AppExceptions', 'AppMetrics', 'AppPageViews', 'AppPerformanceCounters', 'AppRequests', 'AppSystemEvents', 'AppTraces', 'Usage' ]
        metadata: {
          displayName: 'Tables to ignore'
          description: 'A list of the tables to ignore as part of the policy.'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: lawRetentionPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          retentionInDays: { value: '[parameters(\'retentionInDays\')]' }
        }
      }
      {
        policyDefinitionId: lawTableRetentionPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          retentionInDays: { value: '[parameters(\'retentionInDays\')]' }
          ignoreTables: { value: '[parameters(\'ignoreTables\')]' }
        }
      }
    ]
  }
}
