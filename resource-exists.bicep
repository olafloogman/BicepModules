targetScope = 'resourceGroup'

@description('Resource name to check in current scope (resource group)')
param resourceName string

param location string = resourceGroup().location
param utcValue string = utcNow()

// used to pass into deployment script
var resourceGroupName = resourceGroup().name
var identityName = 'id-deployment-script'

// Azure built-in 'Reader' role definition, used to read resources in current scope (resource group)
var readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource identity_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: identityName
  location: location
}

resource role_assignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroupName,identityName,readerRoleDefinitionId)
  properties: {
    principalId: identity_resource.properties.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/${readerRoleDefinitionId}'
  }
}

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
    scriptContent: 'result=$(az resource list --resource-group ${resourceGroupName} --name ${resourceName}); echo $result; echo $result | jq -c \'{Result: map({name: .name})}\' > $AZ_SCRIPTS_OUTPUT_PATH'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
}

output exists bool = length(resource_exists_script.properties.outputs.Result) > 0
