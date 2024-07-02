// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//==============================================================================
// Parameters
//==============================================================================

@description('Optional. Name of the hub. Used to ensure unique resource names. Default: "finops-hub".')
param hubName string

@description('Optional. Azure location where all resources should be created. See https://aka.ms/azureregions. Default: (resource group location).')
param location string = resourceGroup().location

@allowed([
  'Premium_LRS'
  'Premium_ZRS'
])
@description('Optional. Storage SKU to use. LRS = Lowest cost, ZRS = High availability. Note Standard SKUs are not available for Data Lake gen2 storage. Allowed: Premium_LRS, Premium_ZRS. Default: Premium_LRS.')
param storageSku string = 'Premium_LRS'

@description('Optional. Tags to apply to all resources. We will also add the cm-resource-parent tag for improved cost roll-ups in Cost Management.')
param tags object = {}

@description('Optional. Tags to apply to resources based on their resource type. Resource type specific tags will be merged with tags for all resources.')
param tagsByResource object = {}

@description('Optional. List of scope IDs to monitor and ingest cost for.')
param scopesToMonitor array

@description('Optional. Number of days of cost data to retain in the ms-cm-exports container. Default: 0.')
param exportRetentionInDays int = 0

@description('Optional. Number of months of cost data to retain in the ingestion container. Default: 13.')
param ingestionRetentionInMonths int = 13

@description('Optional. Remote storage account for ingestion dataset.')
param remoteHubStorageUri string = ''

@description('Optional. Storage account key for remote storage account.')
@secure()
param remoteHubStorageKey string = ''

@description('Optional. Enable telemetry to track anonymous module usage trends, monitor for bugs, and improve future releases.')
param enableDefaultTelemetry bool = true

//------------------------------------------------------------------------------
// Variables
//------------------------------------------------------------------------------

// Add cm-resource-parent to group resources in Cost Management
var finOpsToolkitVersion = loadTextContent('ftkver.txt')
var resourceTags = union(tags, {
  'cm-resource-parent': '${resourceGroup().id}/providers/Microsoft.Cloud/hubs/${hubName}'
  'ftk-version': finOpsToolkitVersion
  'ftk-tool': 'FinOps hubs'
})

// Generate globally unique Data Factory name: 3-63 chars; letters, numbers, non-repeating dashes
var uniqueSuffix = uniqueString(hubName, resourceGroup().id)
var dataFactoryPrefix = '${replace(hubName, '_', '-')}-engine'
var dataFactorySuffix = '-${uniqueSuffix}'
var dataFactoryName = replace(
  '${take(dataFactoryPrefix, 63 - length(dataFactorySuffix))}${dataFactorySuffix}',
  '--',
  '-'
)

// The last segment of the telemetryId is used to identify this module
var telemetryId = '00f120b5-2007-6120-0000-40b000000000'

//==============================================================================
// Resources
//==============================================================================

//------------------------------------------------------------------------------
// Telemetry
// Used to anonymously count the number of times the template has been deployed
// and to track and fix deployment bugs to ensure the highest quality.
// No information about you or your cost data is collected.
//------------------------------------------------------------------------------

resource defaultTelemetry 'Microsoft.Resources/deployments@2022-09-01' = if (enableDefaultTelemetry) {
  name: 'pid-${telemetryId}-${uniqueString(deployment().name, location)}'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      metadata: {
        _generator: {
          name: 'FinOps toolkit'
          version: finOpsToolkitVersion
        }
      }
      resources: []
    }
  }
}

//------------------------------------------------------------------------------
// Register EventGrid provider so that the data factory trigger can run.
//------------------------------------------------------------------------------

resource RegisterEventGridProvider 'Microsoft.EventGrid/namespaces@2023-12-15-preview' = {
  name: '${uniqueSuffix}-registerRP'
  location: location
  sku: {
    capacity: 1
    name: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

resource cleanupidentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${uniqueSuffix}-cleanupidentity'
  location: location
}

// Assign access to the identity
resource cleanupRegisterEventGridProvider 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  dependsOn: [
    RegisterEventGridProvider
    cleanupidentity
  ]
  name: guid('1e241071-0855-49ea-94dc-649edcd759de', cleanupidentity.id)
  scope: RegisterEventGridProvider
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '1e241071-0855-49ea-94dc-649edcd759de'
    ) //event grid contributor role
    principalId: cleanupidentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// run cleanup script to remove the eventgrid namespace created to register the eventgrid provider

resource eventProviderRegisterResourceCleanup 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  dependsOn: [
    dataFactory
    cleanupRegisterEventGridProvider
  ]
  name: '${uniqueSuffix}-EventGridCleanup'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cleanupidentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '8.0'
    scriptContent: 'Remove-AzResource -Id $env:resourceId -Force'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'resourceId'
        value: RegisterEventGridProvider.id
      }
    ]
  }
}

//------------------------------------------------------------------------------
// ADLSv2 storage account for staging and archive
//------------------------------------------------------------------------------

module storage 'storage.bicep' = {
  name: 'storage'
  params: {
    hubName: hubName
    uniqueSuffix: uniqueSuffix
    sku: storageSku
    location: location
    tags: resourceTags
    tagsByResource: tagsByResource
    scopesToMonitor: scopesToMonitor
    msexportRetentionInDays: exportRetentionInDays
    ingestionRetentionInMonths: ingestionRetentionInMonths
  }
}

//------------------------------------------------------------------------------
// Data Factory and pipelines
//------------------------------------------------------------------------------

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  dependsOn: [
    RegisterEventGridProvider
  ]
  location: location
  tags: union(
    resourceTags,
    contains(tagsByResource, 'Microsoft.DataFactory/factories') ? tagsByResource['Microsoft.DataFactory/factories'] : {}
  )
  identity: { type: 'SystemAssigned' }
  properties: union(
    // Using union() to hide the error that gets surfaced because globalConfigurations is not in the ADF schema yet.
    {},
    {
      globalConfigurations: {
        PipelineBillingEnabled: 'true'
      }
    }
  )
}

module dataFactoryResources 'dataFactory.bicep' = {
  name: 'dataFactoryResources'
  dependsOn: [
    dataFactory
  ]
  params: {
    dataFactoryName: dataFactory.name
    storageAccountName: storage.outputs.name
    exportContainerName: storage.outputs.exportContainer
    configContainerName: storage.outputs.configContainer
    ingestionContainerName: storage.outputs.ingestionContainer
    keyVaultName: keyVault.outputs.name
    location: location
    hubName: hubName
    remoteHubStorageUri: remoteHubStorageUri
    tags: resourceTags
    tagsByResource: tagsByResource
  }
}

//------------------------------------------------------------------------------
// Key Vault for storing secrets
//------------------------------------------------------------------------------

module keyVault 'keyVault.bicep' = {
  name: 'keyVault'
  params: {
    hubName: hubName
    uniqueSuffix: uniqueSuffix
    location: location
    tags: resourceTags
    tagsByResource: tagsByResource
    storageAccountKey: remoteHubStorageKey
    accessPolicies: [
      {
        objectId: dataFactory.identity.principalId
        tenantId: subscription().tenantId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

//==============================================================================
// Outputs
//==============================================================================

@description('Name of the deployed hub instance.')
output name string = hubName

@description('Azure resource location resources were deployed to.')
output location string = location

@description('Name of the Data Factory.')
output dataFactorytName string = dataFactory.name

@description('Resource ID of the storage account created for the hub instance. This must be used when creating the Cost Management export.')
output storageAccountId string = storage.outputs.resourceId

@description('Name of the storage account created for the hub instance. This must be used when connecting FinOps toolkit Power BI reports to your data.')
output storageAccountName string = storage.outputs.name

@description('URL to use when connecting custom Power BI reports to your data.')
output storageUrlForPowerBI string = 'https://${storage.outputs.name}.dfs.${environment().suffixes.storage}/${storage.outputs.ingestionContainer}'

@description('Object ID of the Data Factory managed identity. This will be needed when configuring managed exports.')
output managedIdentityId string = dataFactory.identity.principalId

@description('Azure AD tenant ID. This will be needed when configuring managed exports.')
output managedIdentityTenantId string = tenant().tenantId
