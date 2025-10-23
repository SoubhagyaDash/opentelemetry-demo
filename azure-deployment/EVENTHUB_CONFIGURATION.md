# EventHub Configuration for OpenTelemetry Demo

This document explains how to configure the OpenTelemetry demo applications to use Azure EventHub instead of Kafka.

## EventHub Resources Created

The Bicep deployment creates the following EventHub resources:

1. **EventHub Namespace** - `${projectName}-eventhub-${environment}-${uniqueSuffix}`
2. **EventHub** - `otel-events`
3. **Authorization Rule** - `OtelDemoAccessPolicy` (with Listen, Send, Manage rights)
4. **Consumer Groups**:
   - `accounting` - For the accounting service
   - `fraud-detection` - For the fraud detection service

## Connection Configuration

### Connection String
The EventHub connection string is automatically stored in Azure Key Vault as a secret named `EventHubConnectionString`. The applications can retrieve this using the managed identity.

### Environment Variables
The following environment variables should be set for services that need EventHub access:

```bash
# EventHub connection string (retrieved from Key Vault)
EVENTHUB_CONNECTION_STRING="Endpoint=sb://..."

# EventHub name
EVENTHUB_NAME="otel-events"

# Consumer group (service-specific)
EVENTHUB_CONSUMER_GROUP="accounting"  # or "fraud-detection"
```

## Service Configuration

### Accounting Service (.NET)
Update the accounting service configuration to use EventHub instead of Kafka:

```csharp
// Program.cs or Startup.cs
services.Configure<EventHubOptions>(options =>
{
    options.ConnectionString = Environment.GetEnvironmentVariable("EVENTHUB_CONNECTION_STRING");
    options.EventHubName = Environment.GetEnvironmentVariable("EVENTHUB_NAME");
    options.ConsumerGroup = Environment.GetEnvironmentVariable("EVENTHUB_CONSUMER_GROUP");
});
```

### Fraud Detection Service (Java)
Update the fraud detection service to use EventHub:

```java
// application.properties
eventhub.connection-string=${EVENTHUB_CONNECTION_STRING}
eventhub.name=${EVENTHUB_NAME}
eventhub.consumer-group=${EVENTHUB_CONSUMER_GROUP}
```

### Checkout Service (Go)
Update the checkout service configuration:

```go
// main.go
eventHubConfig := eventhub.Config{
    ConnectionString: os.Getenv("EVENTHUB_CONNECTION_STRING"),
    EventHubName:     os.Getenv("EVENTHUB_NAME"),
}
```

## Kubernetes Deployment Updates

Update the Kubernetes manifests to include EventHub environment variables:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: accounting
spec:
  template:
    spec:
      containers:
      - name: accounting
        env:
        - name: EVENTHUB_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: eventhub-secret
              key: connection-string
        - name: EVENTHUB_NAME
          value: "otel-events"
        - name: EVENTHUB_CONSUMER_GROUP
          value: "accounting"
```

## Creating Kubernetes Secrets

Create a Kubernetes secret with the EventHub connection string:

```bash
# Get the connection string from Azure
CONNECTION_STRING=$(az eventhubs authorization-rule keys list \
  --resource-group otel-demo-rg \
  --namespace-name <eventhub-namespace> \
  --authorization-rule-name OtelDemoAccessPolicy \
  --query primaryConnectionString -o tsv)

# Create Kubernetes secret
kubectl create secret generic eventhub-secret \
  --from-literal=connection-string="$CONNECTION_STRING" \
  -n otel-demo
```

## Azure Key Vault Integration

If using Azure Key Vault CSI driver, create a SecretProviderClass:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: eventhub-secrets
  namespace: otel-demo
spec:
  provider: azure
  parameters:
    useVMManagedIdentity: "true"
    userAssignedIdentityClientID: "<managed-identity-client-id>"
    keyvaultName: "<key-vault-name>"
    objects: |
      array:
        - |
          objectName: EventHubConnectionString
          objectType: secret
          objectVersion: ""
  secretObjects:
  - secretName: eventhub-secret
    type: Opaque
    data:
    - objectName: EventHubConnectionString
      key: connection-string
```

## EventHub vs Kafka Differences

### Message Format
EventHub is compatible with Kafka protocol, so most Kafka client libraries work with minimal changes.

### Partitioning
- EventHub uses partitions similar to Kafka
- Default: 2 partitions for the demo
- Can be increased based on throughput requirements

### Consumer Groups
- EventHub consumer groups work similarly to Kafka
- Each service should use its own consumer group
- Pre-created groups: `accounting`, `fraud-detection`

### Retention
- Default message retention: 1 day
- Can be increased up to 7 days for Standard tier
- Premium tier supports up to 90 days

## Monitoring and Troubleshooting

### Azure Portal
Monitor EventHub metrics in the Azure Portal:
- Incoming messages
- Outgoing messages
- Throttled requests
- Server errors

### Application Insights
EventHub operations are automatically tracked in Application Insights when using Azure SDK.

### Common Issues

1. **Connection Failures**
   - Verify connection string format
   - Check firewall rules
   - Validate managed identity permissions

2. **Message Processing Errors**
   - Check consumer group configuration
   - Verify message format compatibility
   - Monitor EventHub metrics for errors

3. **Performance Issues**
   - Consider increasing throughput units
   - Optimize partition distribution
   - Review consumer group lag

## Security Considerations

1. **Managed Identity** - Services use managed identity for authentication
2. **Connection Strings** - Stored securely in Key Vault
3. **Network Security** - EventHub namespace supports virtual network integration
4. **Access Control** - Fine-grained permissions using Azure RBAC

## Scaling

### Throughput Units
- Standard tier: 1-20 throughput units
- Each unit provides 1 MB/s ingress, 2 MB/s egress
- Auto-inflate can be enabled for automatic scaling

### Partitions
- More partitions = higher parallelism
- Consider partition count based on consumer instances
- Partition count cannot be decreased after creation

## Cost Optimization

1. **Right-size Throughput Units** - Monitor usage and adjust accordingly
2. **Message Retention** - Reduce retention period if not needed
3. **Capture Feature** - Disable if not using data archival
4. **Reserved Capacity** - Consider for production workloads

## Migration from Kafka

If migrating from an existing Kafka setup:

1. Update client libraries to use EventHub-compatible versions
2. Change connection strings and endpoints
3. Update consumer group names if needed
4. Test message format compatibility
5. Update monitoring and alerting
6. Plan for minimal downtime during switchover
