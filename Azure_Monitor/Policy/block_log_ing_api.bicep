targetScope = 'subscription'

var dcrLogApiPolicyDefinitionName = 'policy-definition-dcr-log-api'
var dcrLogApiPolicyDefinitionPolicySetName = 'policy-set-dcr-log-api'

// Create an Azure Policy for to prevent custom DCR streams from populating Microsoft LAW tables
resource dcrLogApiPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: dcrLogApiPolicyDefinitionName
  properties: {
    policyType: 'Custom'
    displayName: 'Manage Custom DCR Streams to Microsoft Tables'
    description: 'Manage custom streams defined in a data collection rule that populate Microsoft tables.'
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
          description: 'Audit or Deny the ability to populate Microsoft tables.'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field:'type'
            equals: 'Microsoft.Insights/dataCollectionRules'
          }
          {
            field: 'Microsoft.Insights/dataCollectionRules/dataFlows[*]'
            exists: 'true'
          }
          {
            count: {
              field: 'Microsoft.Insights/dataCollectionRules/dataFlows[*]'
              where: {
                allOf: [
                  {
                    count: {
                      field: 'Microsoft.Insights/dataCollectionRules/dataFlows[*].streams[*]'
                      where: {
                        field: 'Microsoft.Insights/dataCollectionRules/dataFlows[*].streams[*]'
                        notLike: 'Microsoft-*'
                      }
                    }
                    greater: 0
                  }
                  {
                    field: 'Microsoft.Insights/dataCollectionRules/dataFlows[*].outputStream'
                    like: 'Microsoft-*'
                  }
                ]
              }
            }
            greater: 0
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
resource dcrLogApiPolicyDefinitionPolicySet 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: dcrLogApiPolicyDefinitionPolicySetName
  properties: {
    policyType: 'Custom'
    displayName: 'Log Ingestion API for Microsoft Tables'
    description: 'Log Ingestion API should not be used to populate Microsoft-delivered Log Analytics Workspace tables.'
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
          description: 'Audit or Deny the ability to populate Microsoft tables.'
        }
      }
    }
    policyDefinitions: [
      {
        policyDefinitionId: dcrLogApiPolicyDefinition.id
        parameters: {
          effect: { value: '[parameters(\'effect\')]' }
        }
      }
    ]
  }
}
