targetScope = 'subscription'

var lawTargetedTableRetentionPolicyDefinitionName = 'policy-definition-law-targeted-table-retention'
var lawTargetedTableRetentionPolicySetName = 'policy-set-law-targeted-table-retention'

// Create an Azure Policy for each individual table in a Log Analytics Workspace
resource lawTargetedTableRetentionPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: lawTargetedTableRetentionPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Table Retention - Targeted'
    description: 'Verifies all tables with a specific name have their retention set appropriately.'
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
      includeTables: {
        type: 'Array'
        metadata: {
          displayName: 'Tables to include in the retention check.'
          description: 'A list of the tables to include in the retention check as part of the policy.'
        }
      }
      retentionInDays: {
        type: 'Integer'
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
            equals: 'Microsoft.OperationalInsights/workspaces/tables'
          }
          {
            field: 'Microsoft.OperationalInsights/workspaces/tables/schema.name'
            in: '[parameters(\'includeTables\')]'
          }
          {
            field: 'Microsoft.OperationalInsights/workspaces/tables/retentionInDays'
            notEquals: '[parameters(\'retentionInDays\')]'
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
resource lawTargetedTableRetentionPolicySet 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: lawTargetedTableRetentionPolicySetName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Analytics Workspace Retention - Targeted Tables'
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
      includeTables: {
        type: 'Array'
        metadata: {
          displayName: 'Tables to include in the retention check.'
          description: 'A list of the tables to include in the retention check as part of the policy.'
        }
      }
      retentionInDays: {
      type: 'Integer'
      metadata: {
        displayName: 'Retention In Days'
        description: 'The maximum number of days of retention for a table.'
      }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: lawTargetedTableRetentionPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          includeTables: { value: '[parameters(\'includeTables\')]' }
          retentionInDays: { value: '[parameters(\'retentionInDays\')]' }
        }
      }
    ]
  }
}
