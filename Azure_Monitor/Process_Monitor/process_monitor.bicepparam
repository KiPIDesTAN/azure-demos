using './process_monitor.bicep'

param appIdentifier = 'appIdentifier'     // A generic application identifier that gets added to the name of all the resources created by this demo.
param vmAdminUsername = 'azureuser'   // Username on the VM
param sshPublicKey = '<sshPublicKey>' // SSH public key for ssh access to the VM
