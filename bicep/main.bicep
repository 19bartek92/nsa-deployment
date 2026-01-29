@description('Azure region for all resources')
param location string = resourceGroup().location

// ============================================================================
// SHARED INFRASTRUCTURE REFERENCES (from Eureka RG)
// ============================================================================

@description('Name of the Resource Group containing shared infrastructure (Eureka deployment)')
param sharedResourceGroupName string = 'rg-eureka-crawler'

@description('Name of the existing Container Apps Environment (from Eureka deployment)')
param environmentName string = 'env-eureka-crawler'

@description('Name of the existing User-Assigned Managed Identity (from Eureka deployment)')
param uamiName string = 'uami-eureka-crawler'

@description('Name of the existing Azure Key Vault (from Eureka deployment)')
param keyVaultName string

@description('Name of the existing Azure Container Registry (from Eureka deployment)')
param acrName string

@description('Name of the existing Cosmos DB account (from Eureka deployment)')
param cosmosAccountName string

// ============================================================================
// NSA-SPECIFIC PARAMETERS
// ============================================================================

@description('Name of the NSA backfill job')
param jobBackfillName string = 'nsa-backfill'

@description('Name of the NSA delta job')
param jobDeltaName string = 'nsa-delta'

@description('Container image name in ACR')
param imageName string = 'nsa-crawler'

@description('Container image tag')
param imageTag string = 'latest'

@description('CPU cores for job containers')
param cpu string = '1.0'

@description('Memory for job containers')
param memory string = '2Gi'

@description('CRON expression for delta job schedule (UTC timezone)')
param cronExpression string = '10 5 * * *'

// ============================================================================
// CROSS-RG RESOURCE REFERENCES
// ============================================================================

// Reference existing resources from shared (Eureka) Resource Group
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
  scope: resourceGroup(sharedResourceGroupName)
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
  scope: resourceGroup(sharedResourceGroupName)
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
  scope: resourceGroup(sharedResourceGroupName)
}

resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
  scope: resourceGroup(sharedResourceGroupName)
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' existing = {
  name: cosmosAccountName
  scope: resourceGroup(sharedResourceGroupName)
}

// ============================================================================
// NSA-SPECIFIC RESOURCES (in this RG)
// ============================================================================

// Create NSA Cosmos DB Database in shared Cosmos account
// Note: Database is a child resource, must be in same RG as parent account
// We use a module to deploy it to the shared RG
module cosmosDatabase 'modules/cosmos-database.bicep' = {
  name: 'nsa-cosmos-database'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    cosmosAccountName: cosmosAccountName
    databaseName: 'nsa'
  }
}

// Container Apps Job - NSA Backfill (Manual Trigger)
resource jobBackfill 'Microsoft.App/jobs@2023-05-01' = {
  name: jobBackfillName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 86400 // 24 hours
      replicaRetryLimit: 3
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      secrets: [
        {
          name: 'cosmos-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/cosmos-connection-string'
          identity: uami.id
        }
        {
          name: 'sharepoint-tenant-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-tenant-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-client-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-client-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-client-secret'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-client-secret'
          identity: uami.id
        }
        {
          name: 'sharepoint-site-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-site-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-drive-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-drive-id'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'nsa-crawler-backfill'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'  // Placeholder - developer will update after pushing real image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'MODE', value: 'backfill' }
            // NSA specific configuration
            { name: 'Nsa__BackfillStartDate', value: '2024-01-01' }
            { name: 'Nsa__BackfillEndDate', value: '2024-12-31' }
            { name: 'Nsa__DeltaWindowDays', value: '14' }
            { name: 'Nsa__SixMonthRuleMonths', value: '6' }
            { name: 'Nsa__Limits__RequestsPerMinute', value: '10' }
            { name: 'Nsa__Limits__RequestsPerHour', value: '100' }
            { name: 'Nsa__Limits__MinDelayMs', value: '2000' }
            { name: 'Nsa__Limits__MaxDelayMs', value: '5000' }
            // Cosmos DB - NSA database
            { name: 'Cosmos__Database', value: 'nsa' }
            { name: 'Cosmos__DecisionsCollection', value: 'decisions' }
            { name: 'Cosmos__PendingJustificationsCollection', value: 'pending_justifications' }
            { name: 'Cosmos__FailedDocumentsCollection', value: 'failed_documents' }
            { name: 'Cosmos__FailedSharePointUploadsCollection', value: 'failed_sharepoint_uploads' }
            { name: 'Cosmos__RateLimiterStateCollection', value: 'rate_limiter_state' }
            { name: 'Cosmos__CreateIndexesOnStart', value: 'true' }
            { name: 'Cosmos__ConnectionString', secretRef: 'cosmos-connection-string' }
            // SharePoint - NSA_docs folder
            { name: 'SharePoint__Enabled', value: 'true' }
            { name: 'SharePoint__FolderFormat', value: 'yyyyMM' }
            { name: 'SharePoint__BaseFolder', value: 'NSA_docs' }
            { name: 'SharePoint__TenantId', secretRef: 'sharepoint-tenant-id' }
            { name: 'SharePoint__ClientId', secretRef: 'sharepoint-client-id' }
            { name: 'SharePoint__ClientSecret', secretRef: 'sharepoint-client-secret' }
            { name: 'SharePoint__SiteId', secretRef: 'sharepoint-site-id' }
            { name: 'SharePoint__DriveId', secretRef: 'sharepoint-drive-id' }
            // Conversion (LibreOffice in container)
            { name: 'Conversion__LibreOfficePath', value: '/usr/bin/soffice' }
            { name: 'Conversion__TimeoutSeconds', value: '120' }
            { name: 'Conversion__TempDirectory', value: '/tmp/nsa-conversion' }
            // Logging
            { name: 'Logging__LogLevel__Default', value: 'Information' }
            { name: 'Logging__LogLevel__Microsoft.Hosting.Lifetime', value: 'Information' }
            { name: 'Logging__LogLevel__NSA.Crawler', value: 'Debug' }
          ]
        }
      ]
    }
  }
  dependsOn: [
    cosmosDatabase
  ]
}

// Container Apps Job - NSA Delta (Scheduled Trigger)
resource jobDelta 'Microsoft.App/jobs@2023-05-01' = {
  name: jobDeltaName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 3600 // 1 hour
      replicaRetryLimit: 2
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        parallelism: 1
        replicaCompletionCount: 1
      }
      secrets: [
        {
          name: 'cosmos-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/cosmos-connection-string'
          identity: uami.id
        }
        {
          name: 'sharepoint-tenant-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-tenant-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-client-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-client-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-client-secret'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-client-secret'
          identity: uami.id
        }
        {
          name: 'sharepoint-site-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-site-id'
          identity: uami.id
        }
        {
          name: 'sharepoint-drive-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/sharepoint-drive-id'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'nsa-crawler-delta'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'  // Placeholder - developer will update after pushing real image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'MODE', value: 'delta' }
            // NSA specific configuration
            { name: 'Nsa__BackfillStartDate', value: '2024-01-01' }
            { name: 'Nsa__BackfillEndDate', value: '2024-12-31' }
            { name: 'Nsa__DeltaWindowDays', value: '14' }
            { name: 'Nsa__SixMonthRuleMonths', value: '6' }
            { name: 'Nsa__Limits__RequestsPerMinute', value: '10' }
            { name: 'Nsa__Limits__RequestsPerHour', value: '100' }
            { name: 'Nsa__Limits__MinDelayMs', value: '2000' }
            { name: 'Nsa__Limits__MaxDelayMs', value: '5000' }
            // Cosmos DB - NSA database
            { name: 'Cosmos__Database', value: 'nsa' }
            { name: 'Cosmos__DecisionsCollection', value: 'decisions' }
            { name: 'Cosmos__PendingJustificationsCollection', value: 'pending_justifications' }
            { name: 'Cosmos__FailedDocumentsCollection', value: 'failed_documents' }
            { name: 'Cosmos__FailedSharePointUploadsCollection', value: 'failed_sharepoint_uploads' }
            { name: 'Cosmos__RateLimiterStateCollection', value: 'rate_limiter_state' }
            { name: 'Cosmos__CreateIndexesOnStart', value: 'true' }
            { name: 'Cosmos__ConnectionString', secretRef: 'cosmos-connection-string' }
            // SharePoint - NSA_docs folder
            { name: 'SharePoint__Enabled', value: 'true' }
            { name: 'SharePoint__FolderFormat', value: 'yyyyMM' }
            { name: 'SharePoint__BaseFolder', value: 'NSA_docs' }
            { name: 'SharePoint__TenantId', secretRef: 'sharepoint-tenant-id' }
            { name: 'SharePoint__ClientId', secretRef: 'sharepoint-client-id' }
            { name: 'SharePoint__ClientSecret', secretRef: 'sharepoint-client-secret' }
            { name: 'SharePoint__SiteId', secretRef: 'sharepoint-site-id' }
            { name: 'SharePoint__DriveId', secretRef: 'sharepoint-drive-id' }
            // Conversion (LibreOffice in container)
            { name: 'Conversion__LibreOfficePath', value: '/usr/bin/soffice' }
            { name: 'Conversion__TimeoutSeconds', value: '120' }
            { name: 'Conversion__TempDirectory', value: '/tmp/nsa-conversion' }
            // Logging
            { name: 'Logging__LogLevel__Default', value: 'Information' }
            { name: 'Logging__LogLevel__Microsoft.Hosting.Lifetime', value: 'Information' }
            { name: 'Logging__LogLevel__NSA.Crawler', value: 'Debug' }
          ]
        }
      ]
    }
  }
  dependsOn: [
    cosmosDatabase
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

output jobBackfillName string = jobBackfill.name
output jobDeltaName string = jobDelta.name
output sharedResourceGroup string = sharedResourceGroupName
output nsaResourceGroup string = resourceGroup().name
output fullImageUrl string = '${containerRegistry.properties.loginServer}/${imageName}:${imageTag}'
output updateJobBackfillCommand string = 'az containerapp job update -n ${jobBackfillName} -g ${resourceGroup().name} --image ${containerRegistry.properties.loginServer}/${imageName}:${imageTag} --registry-server ${containerRegistry.properties.loginServer} --registry-identity ${uami.id}'
output updateJobDeltaCommand string = 'az containerapp job update -n ${jobDeltaName} -g ${resourceGroup().name} --image ${containerRegistry.properties.loginServer}/${imageName}:${imageTag} --registry-server ${containerRegistry.properties.loginServer} --registry-identity ${uami.id}'
output deleteNsaCommand string = 'az group delete --name ${resourceGroup().name} --yes  # Safe: only deletes NSA jobs, not shared infrastructure'
