targetScope = 'resourceGroup'

@description('Resource name to check in current scope (resource group)')
param resourceName string

param location string = resourceGroup().location
param utcValue string = utcNow()

// used to pass into deployment script
var resourceGroupName = resourceGroup().name
var identityName = 'id-deployment-script'

// Azure built-in 'Contributor' role definition. Used to check if the resource exits in the current scope, and delete user assigned identity.
var contributorRoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// managed identity to perform az cli commands 
resource identity_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

// assign contributor role to managed identity, so resources can be read and managed identity can be cleaned up
resource role_assignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroupName,identityName,contributorRoleDefinitionId)
  properties: {
    principalId: identity_resource.properties.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/${contributorRoleDefinitionId}'
  }
}

/*
  The script below performs an 'az resource list' command to determine whether a resource exists,
  and deletes the managed identity created above
*/
resource resource_exists_script 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'resource_exists'
  dependsOn: [
    role_assignment
  ]
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity_resource.id}': {}
    }
  }
  properties: {
    forceUpdateTag: utcValue
    azCliVersion: '2.15.0'
    timeout: 'PT10M'
    arguments: '\'${resourceGroupName}\' \'${resourceName}\''
    scriptContent: 'result=$(az resource list --resource-group ${resourceGroupName} --name ${resourceName}); echo $result; echo $result | jq -c \'{Result: map({name: .name})}\' > $AZ_SCRIPTS_OUTPUT_PATH; az identity delete --name ${identityName} --resource-group ${resourceGroupName}'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

output exists bool = length(resource_exists_script.properties.outputs.Result) > 0
