# EventHub Migration Summary

This document summarizes the changes made to migrate from Kafka to Azure EventHub for the fraud-detection and accounting components.

## Components Updated

### 1. Fraud Detection (Kotlin)
- **Location**: `src/fraud-detection/`
- **Language**: Kotlin
- **Framework**: Gradle + Azure SDK for Java

#### Changes Made:
- Updated `build.gradle.kts` to replace Kafka dependencies with Azure EventHub SDK
- Modified `main.kt` to use `EventHubConsumerClient` instead of `KafkaConsumer`
- Implemented managed identity authentication using `DefaultAzureCredential`
- Updated feature flag from `kafkaQueueProblems` to `eventHubQueueProblems`

#### Dependencies:
- **Added**: `com.azure:azure-messaging-eventhubs:5.18.10`
- **Added**: `com.azure:azure-identity:1.13.3`
- **Removed**: `org.apache.kafka:kafka-clients:4.1.0`

### 2. Accounting (C#)
- **Location**: `src/accounting/`
- **Language**: C# (.NET 8)
- **Framework**: .NET + Azure SDK for .NET

#### Changes Made:
- Updated `Accounting.csproj` to replace Confluent.Kafka with Azure EventHub SDK
- Modified `Consumer.cs` to use `EventHubConsumerClient` instead of `KafkaConsumer`
- Implemented managed identity authentication using `DefaultAzureCredential`
- Added async processing support with `ReadEventsAsync`

#### Dependencies:
- **Added**: `Azure.Messaging.EventHubs:5.12.0`
- **Added**: `Azure.Identity:1.12.1`
- **Removed**: `Confluent.Kafka:2.11.0`

## Environment Variables

### Previous (Kafka):
```
KAFKA_ADDR=localhost:9092
```

### New (EventHub):
```
EVENTHUB_NAMESPACE=your-eventhub-namespace
EVENTHUB_NAME=orders  # Optional, defaults to "orders"
```

## Azure Configuration Requirements

### 1. EventHub Setup
- Create an EventHub namespace in Azure
- Create an EventHub entity named "orders" (or configure custom name)
- Configure consumer groups: "fraud-detection" and "accounting"

### 2. Authentication Setup
- Enable Managed Identity on your container instances/services
- Assign the following roles to the managed identities:
  - `Azure Event Hubs Data Receiver` (for consumer components)
  - `Azure Event Hubs Data Sender` (for producer - checkout component)

### 3. Network Configuration
- Ensure container/service can reach `*.servicebus.windows.net` on port 5671 (AMQP over TLS)
- Configure any necessary firewall rules or virtual network settings

## Key Benefits

1. **Secure Authentication**: Uses managed identity instead of connection strings
2. **Azure Native**: Fully integrated with Azure security and monitoring
3. **Scalability**: EventHub provides better scaling capabilities than self-managed Kafka
4. **Monitoring**: Native integration with Azure Monitor and Application Insights
5. **Reliability**: Built-in redundancy and disaster recovery features

## Migration Checklist

- [ ] Deploy EventHub namespace and entity
- [ ] Configure managed identities for container services
- [ ] Assign proper RBAC roles
- [ ] Update environment variables in deployment configurations
- [ ] Test the end-to-end flow: checkout → eventhub → fraud-detection & accounting
- [ ] Monitor logs and metrics to ensure proper operation

## Troubleshooting

### Common Issues:
1. **Authentication Errors**: Verify managed identity is enabled and has proper roles
2. **Connection Errors**: Check network connectivity and firewall rules
3. **Consumer Group Errors**: Ensure consumer groups exist in EventHub
4. **Message Format Issues**: Verify protobuf serialization/deserialization is working correctly

### Logs to Monitor:
- Fraud Detection: Look for "Consumed event with orderId" messages
- Accounting: Look for "Order parsing" and database operation messages
- Checkout: Look for "Successfully sent message to EventHub" messages