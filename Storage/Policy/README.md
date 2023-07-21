# Policy

This folder contains Azure Policy applications for Storage.

## Deployment

The commands below will deploy the policy files. They are written for PowerShell syntax. Changing them to bash should be straight forward. The commands below assume your az cli is already logged into the right account and the subscription is set appropriately.

If you are deploying at the subscription, use the command below.

__NOTE:__ A parameter file may not always be required.

```pwsh
az deployment sub create --location <location> --template-file <filname.bicep> --parameters <parameter-file.bicepparam>
```

## Lifecycle Management Rule - Blob Deletion

The lifecycle management rule - blob deletion is a policy that checks to make sure there is exactly one rule for deleting documents X days after its creation. There can only be one delete action based on the create date and that date must be the value set within the policy.

The purpose of this policy is to force specific data retention requirements.

This policy may also have a requirement that at least one policy exists.

### Demo Files

- storage_lmr_detection.bicep
