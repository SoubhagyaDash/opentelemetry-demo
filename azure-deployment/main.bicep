// OpenTelemetry Demo - Azure Kubernetes Service Deployment
// This Bicep template deploys the complete OpenTelemetry demo infrastructure on AKS

targetScope = 'resourceGroup'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
param projectName string = 'otel-demo-v1'

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('AKS cluster name')
param aksClusterName string = '${projectName}-aks-${environment}'

@description('Node pool VM size')
param nodeVmSize string = 'Standard_D4s_v3'

@description('Initial node count')
param nodeCount int = 3

@description('Maximum pods per node')
param maxPodsPerNode int = 30

@description('Enable Azure Monitor for containers')
param enableAzureMonitor bool = true

@description('Enable Azure Key Vault integration')
param enableKeyVault bool = true

@description('Enable Azure Container Registry')
param enableAcr bool = true

@description('Enable Azure EventHub')
param enableEventHub bool = true

@description('EventHub SKU (Basic, Standard, Premium)')
param eventHubSku string = 'Standard'

@description('EventHub throughput units (1-20 for Standard, 1-100 for Premium)')
param eventHubThroughputUnits int = 2

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Application: 'OpenTelemetry-Demo'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var acrName = 'oteldemo${uniqueSuffix}acr'  // Removed hyphens and reordered to avoid invalid characters
var keyVaultName = '${projectName}-kv-${uniqueSuffix}'
var logAnalyticsName = '${projectName}-logs-${environment}'
var appInsightsName = '${projectName}-insights-${environment}'
var vnetName = '${projectName}-vnet-${environment}'
var subnetName = 'aks-subnet'
var managedIdentityName = '${projectName}-identity-${environment}'
var eventHubNamespaceName = '${projectName}-eventhub-${environment}-${uniqueSuffix}'
var eventHubName = 'otel-events'

// Virtual Network for AKS
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.0.0/22'
        }
      }
    ]
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Managed Identity for AKS
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = if (enableAcr) {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// Role assignment for AKS to pull from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAcr) {
  scope: acr
  name: guid(acr.id, managedIdentity.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure EventHub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = if (enableEventHub) {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubThroughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: true
  }
}

// EventHub for OpenTelemetry events
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = if (enableEventHub) {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 2
    status: 'Active'
  }
}

// EventHub Authorization Rule for applications
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = if (enableEventHub) {
  parent: eventHubNamespace
  name: 'OtelDemoAccessPolicy'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

// Consumer Group for Accounting Service
resource accountingConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (enableEventHub) {
  parent: eventHub
  name: 'accounting'
  properties: {
    userMetadata: 'Consumer group for accounting service'
  }
}

// Consumer Group for Fraud Detection Service
resource fraudDetectionConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = if (enableEventHub) {
  parent: eventHub
  name: 'fraud-detection'
  properties: {
    userMetadata: 'Consumer group for fraud detection service'
  }
}

// Role assignment for managed identity to access EventHub
resource eventHubDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableEventHub) {
  scope: eventHubNamespace
  name: guid(eventHubNamespace.id, managedIdentity.id, 'EventHubDataOwner')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec') // Azure Event Hubs Data Owner
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = if (enableKeyVault) {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: false
  }
}

// Store EventHub connection string in Key Vault
resource eventHubConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (enableKeyVault && enableEventHub) {
  parent: keyVault
  name: 'EventHubConnectionString'
  properties: {
    // value: empty(eventHubAuthRule) ? '': empty(eventHubAuthRule.listKeys()) ? '':eventHubAuthRule.listKeys().primaryConnectionString
    value: eventHubAuthRule!.listKeys()!.primaryConnectionString
    contentType: 'Connection String'
    attributes: {
      enabled: true
    }
  }
  // dependsOn: [
  //  eventHubAuthRule
  //]
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: '${projectName}-${environment}'
    agentPoolProfiles: [
      {
        name: 'default'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osDiskSizeGB: 100
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        vnetSubnetID: vnet.properties.subnets[0].id
        maxPods: maxPodsPerNode
      }
    ]
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    nodeResourceGroup: '${resourceGroup().name}-aks-nodes'
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.2.0.0/16'
      dnsServiceIP: '10.2.0.10'
    }
    addonProfiles: enableAzureMonitor ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
      azureKeyvaultSecretsProvider: enableKeyVault ? {
        enabled: true
      } : {
        enabled: false
      }
    } : {}
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
    disableLocalAccounts: false
  }
}

// Output values
output aksClusterName string = aksCluster.name
// output acrLoginServer string = acr.properties.loginServer
// output keyVaultUri string = keyVault.properties.vaultUri
output managedIdentityClientId string = managedIdentity.properties.clientId
output logAnalyticsWorkspaceId string = logAnalytics.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output eventHubNamespaceName string = enableEventHub && eventHubNamespace != null ? eventHubNamespace.name : ''
output eventHubName string = enableEventHub && eventHub != null ? eventHub.name : ''
output resourceGroupName string = resourceGroup().name
output location string = location
