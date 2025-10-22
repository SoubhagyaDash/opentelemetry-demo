# Azure EventHub Integration

This checkout service has been modified to use Azure EventHub instead of Kafka for message publishing.

## Changes Made

1. **Replaced Kafka dependencies** with Azure EventHub SDK:
   - Removed: `github.com/IBM/sarama`
   - Added: `github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs`
   - Added: `github.com/Azure/azure-sdk-for-go/sdk/azidentity`

2. **Created new EventHub client package** (`eventhub/producer.go`):
   - Implements EventHub producer using managed identity authentication
   - Maintains similar interface to the original Kafka producer
   - Includes proper error handling and logging

3. **Updated main application**:
   - Modified checkout struct to use EventHub producer instead of Kafka
   - Updated environment variable configuration
   - Maintained OpenTelemetry tracing with EventHub-specific attributes
   - Preserved feature flag functionality for queue overload simulation

## Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `EVENTHUB_NAMESPACE` | Azure EventHub namespace name (without .servicebus.windows.net suffix) | `my-eventhub-namespace` |
| `EVENTHUB_NAME` | EventHub entity name (optional, defaults to "orders") | `orders` |

## Authentication

The service uses **Azure Managed Identity** for authentication to EventHub. Ensure the container/service has:

1. Managed Identity enabled
2. Appropriate RBAC permissions on the EventHub:
   - `Azure Event Hubs Data Sender` role on the EventHub or namespace

## Container Deployment

When deploying in containers (AKS, ACI, etc.), ensure:

1. Managed Identity is enabled for the container/pod
2. The identity has the required EventHub permissions
3. Environment variables are properly configured

## Differences from Kafka

- **Authentication**: Uses managed identity instead of broker addresses
- **Configuration**: Requires namespace and EventHub name instead of broker list
- **Error Handling**: Synchronous sends with immediate error feedback
- **Tracing**: Updated to use EventHub-specific semantic conventions

## Feature Flags

The service still supports the queue overload simulation feature flag:
- `eventHubQueueProblems`: Integer value to simulate additional message sends

## Monitoring

OpenTelemetry traces include EventHub-specific attributes:
- `messaging.eventhub.namespace`
- `messaging.eventhub.producer.success`
- `messaging.eventhub.producer.duration_ms`
- `messaging.message.body.size`