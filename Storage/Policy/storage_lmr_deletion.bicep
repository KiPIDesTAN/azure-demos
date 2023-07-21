targetScope = 'subscription'

var storageBlobDeletionPolicyDefinitionName = 'policy-definition-storage-lmr-deletion'
var storeageLmrDeletionPolicySetName = 'policy-set-storage-lmr-deletion'

// Create an Azure Policy to check that blob deletion is set to a specific number of days.
resource storageBlobDeletionPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: storageBlobDeletionPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Storage Lifecycle Management Rule Blob Deletion at Specific Day'
    description: 'Verifies there is one Lifecycle Management Rule where blob deletion is set to a specific day.'
    mode: 'All'
    metadata: {
      category: 'Storage'
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
          description: 'Audit or Deny blob storage lifecycle management rules that violate specific deletion requirements.'
        }
      }
      daysAfterCreationGreaterThan: {
        type: 'Integer'
        metadata: {
          displayName: 'Days After Creation Greater Than '
          description: 'The number of days the days after creation should be greater than.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Storage/storageAccounts/managementPolicies'
          }
          {
            count: {
              field: 'Microsoft.Storage/storageAccounts/managementPolicies/policy.rules[*]'
              where: {
                allOf: [
                  {
                    field: 'Microsoft.Storage/storageAccounts/managementPolicies/policy.rules[*].definition.actions.baseBlob.delete.daysAfterCreationGreaterThan'
                    notEquals: '[parameters(\'daysAfterCreationGreaterThan\')]'
                  }
                ]
              }
            }
            greater: 0
          }
          {
            count: {
              field: 'Microsoft.Storage/storageAccounts/managementPolicies/policy.rules[*]'
              where: {
                allOf: [
                  {
                    field: 'Microsoft.Storage/storageAccounts/managementPolicies/policy.rules[*].definition.actions.baseBlob.delete.daysAfterCreationGreaterThan'
                    equals: '[parameters(\'daysAfterCreationGreaterThan\')]'
                  }
                ]
              }
            }
            equals: 1
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
resource storeageLmrDeletionPolicySet 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: storeageLmrDeletionPolicySetName
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
      daysAfterCreationGreaterThan: {
        type: 'Integer'
        metadata: {
          displayName: 'Days After Creation Greater Than '
          description: 'The number of days the days after creation should be greater than.'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: storageBlobDeletionPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
          daysAfterCreationGreaterThan: { value: '[parameters(\'daysAfterCreationGreaterThan\')]' }
        }
      }
    ]
  }
}
