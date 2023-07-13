using './01_resources.bicep'

param appIdentifier = '<app-identifier>' // Identifier added to all the resources created by this deployment
param principalId = '<principalId>' // Principal ID of the person to add to the Monitoring Data Reader role on the newly created Azure Monitor Workspace

