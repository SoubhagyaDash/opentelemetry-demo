# OpenTelemetry Demo - Azure Kubernetes Service Deployment

This directory contains Bicep templates and scripts to deploy the OpenTelemetry demo application on Azure Kubernetes Service (AKS).

## Architecture Overview

The deployment creates the following Azure components:

### Core Infrastructure
- **Azure Kubernetes Service (AKS)** - Managed Kubernetes cluster
- **Virtual Network** - Dedicated network for the AKS cluster
- **Managed Identity** - For secure access to Azure resources
- **Azure Container Registry (ACR)** - For storing container images
- **Azure Event Hubs** - Message streaming platform (replaces Kafka)
- **Log Analytics Workspace** - For centralized logging
- **Application Insights** - For application monitoring

### Deployed Applications
The following microservices will be deployed on the AKS cluster:

#### Core Demo Services
1. **Accounting Service** (.NET) - Handles financial transactions
2. **Ad Service** (Java) - Serves advertisements
3. **Cart Service** (.NET) - Shopping cart functionality
4. **Checkout Service** (Go) - Order processing
5. **Currency Service** (C++) - Currency conversion
6. **Email Service** (Ruby) - Email notifications
7. **Fraud Detection Service** (Java) - Fraud detection using EventHub
8. **Frontend** (Next.js) - Web user interface
9. **Frontend Proxy** (Envoy) - Load balancer and proxy
10. **Image Provider** (Nginx) - Static image serving
11. **Load Generator** (Python/Locust) - Traffic generation
12. **Payment Service** (JavaScript) - Payment processing
13. **Product Catalog Service** (Go) - Product information
14. **Quote Service** (PHP) - Shipping quotes
15. **Recommendation Service** (Python) - Product recommendations
16. **Shipping Service** (Rust) - Shipping calculations

#### Dependent Services
17. **Flagd** - Feature flag service
18. **Flagd UI** (Elixir) - Feature flag management UI
19. **PostgreSQL** - Database for accounting service
20. **Valkey/Redis** - Cache for cart service

#### Telemetry Components
21. **OpenTelemetry Collector** - Telemetry data collection and export
22. **Jaeger** - Distributed tracing backend
23. **Grafana** - Observability dashboards
24. **Prometheus** - Metrics collection and storage
25. **OpenSearch** - Log aggregation and search

### Network Configuration
- **Virtual Network**: 10.0.0.0/16 (65,536 IPs)
- **AKS Subnet**: 10.0.0.0/22 (1,024 IPs)
- **Service CIDR**: 10.2.0.0/16 (for Kubernetes services)
- **DNS Service IP**: 10.2.0.10

The /22 subnet provides sufficient IP addresses for:
- 3 nodes × 30 pods/node = 90 pod IPs
- Additional IPs for node management and scaling
- Room for horizontal scaling up to ~30 nodes

## Prerequisites

1. **Azure CLI** installed and configured
2. **Azure subscription** with appropriate permissions
3. **Bicep CLI** installed
4. **kubectl** installed
5. **Helm** (optional, for Kubernetes deployments)

## Deployment Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/open-telemetry/opentelemetry-demo.git
cd opentelemetry-demo/azure-deployment
```

### 2. Configure Parameters
Edit `main.parameters.json` to customize your deployment:
- Change `location` to your preferred Azure region
- Adjust `nodeVmSize` and `nodeCount` based on your requirements
- Modify `tags` as needed for your organization

### 3. Create Resource Group
```bash
az group create --name otel-demo-rg --location "East US 2"
```

### 4. Deploy Infrastructure
```bash
az deployment group create \
  --resource-group otel-demo-rg \
  --template-file main.bicep \
  --parameters @main.parameters.json
```

### 5. Get AKS Credentials
```bash
az aks get-credentials --resource-group otel-demo-rg --name otel-demo-aks-dev
```

### 6. Deploy Applications
```bash
# Create the namespace
kubectl create namespace otel-demo

# Apply the Kubernetes manifests to the otel-demo namespace
kubectl apply -f ../kubernetes/opentelemetry-demo.yaml -n otel-demo

# Or use Helm (if available) 
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install otel-demo open-telemetry/opentelemetry-demo -n otel-demo --create-namespace
```

### 7. Access the Application
```bash
# Get the frontend service external IP
kubectl get services -n otel-demo

# Port forward for local access (alternative)
kubectl port-forward -n otel-demo svc/frontend 8080:8080
```

### 8. Configure EventHub Integration
After deploying the infrastructure, you need to configure the services to use EventHub:

### 8. Configure EventHub Integration
After deploying the infrastructure, you need to configure the services to use EventHub:

#### 8.1. Automated Configuration (Recommended)
Use the provided script to automatically configure EventHub integration:

```bash
# Linux/macOS
chmod +x configure-eventhub.sh
./configure-eventhub.sh

# Windows PowerShell
.\configure-eventhub.ps1
```

#### 8.2. Manual Configuration
If you prefer manual configuration:

```bash
# Get EventHub connection string from deployment outputs
EVENTHUB_CONNECTION_STRING=$(az deployment group show \
  --resource-group otel-demo-rg \
  --name otel-demo-deployment \
  --query 'properties.outputs.eventHubConnectionString.value' \
  --output tsv)

# Create Kubernetes secret
kubectl create secret generic eventhub-secret \
  --from-literal=connection-string="$EVENTHUB_CONNECTION_STRING" \
  -n otel-demo
```

Apply the EventHub configuration patches:

```bash
# Configure checkout service (producer)
kubectl patch deployment checkout -n otel-demo --type='merge' --patch='
spec:
  template:
    spec:
      containers:
      - name: checkout
        env:
        - name: EVENTHUB_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: eventhub-secret
              key: connection-string
        - name: EVENTHUB_NAME
          value: "otel-events"
        - name: EVENTHUB_ENABLED
          value: "true"'

# Configure accounting service (consumer)
kubectl patch deployment accounting -n otel-demo --type='merge' --patch='
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
        - name: EVENTHUB_ENABLED
          value: "true"'

# Configure fraud detection service (consumer)
kubectl patch deployment fraud-detection -n otel-demo --type='merge' --patch='
spec:
  template:
    spec:
      containers:
      - name: fraud-detection
        env:
        - name: EVENTHUB_CONNECTION_STRING
          valueFrom:
            secretKeyRef:
              name: eventhub-secret
              key: connection-string
        - name: EVENTHUB_NAME
          value: "otel-events"
        - name: EVENTHUB_CONSUMER_GROUP
          value: "fraud-detection"
        - name: EVENTHUB_ENABLED
          value: "true"'
```

#### 8.3. Verify EventHub Configuration
```bash
# Check configuration
./configure-eventhub.sh verify  # Linux/macOS
.\configure-eventhub.ps1 -Action verify  # Windows

# Test connectivity
./configure-eventhub.sh test  # Linux/macOS
.\configure-eventhub.ps1 -Action test  # Windows

# Monitor logs
kubectl logs -n otel-demo deployment/checkout --follow
kubectl logs -n otel-demo deployment/accounting --follow
kubectl logs -n otel-demo deployment/fraud-detection --follow
```

## EventHub Integration Details

### Application Code Changes Required

The services need to be modified to use EventHub instead of Kafka. Here are the specific changes:

#### Checkout Service (Go) - Producer
The checkout service needs to publish order events to EventHub:

```go
// Add EventHub client initialization
import (
    "github.com/Azure/azure-event-hubs-go/v3"
    "github.com/Azure/azure-amqp-common-go/v4/conn"
)

// Initialize EventHub producer
func initEventHubProducer() (*eventhub.Hub, error) {
    connectionString := os.Getenv("EVENTHUB_CONNECTION_STRING")
    eventHubName := os.Getenv("EVENTHUB_NAME")
    
    if connectionString == "" {
        // Fallback to Kafka if EventHub not configured
        return nil, nil
    }
    
    hub, err := eventhub.NewHubFromConnectionString(connectionString)
    if err != nil {
        return nil, fmt.Errorf("failed to create EventHub client: %v", err)
    }
    
    return hub, nil
}

// Send order event to EventHub
func sendOrderEvent(hub *eventhub.Hub, orderData []byte) error {
    if hub == nil {
        // Use existing Kafka logic as fallback
        return sendToKafka(orderData)
    }
    
    event := eventhub.NewEvent(orderData)
    event.Properties = map[string]interface{}{
        "eventType": "order_placed",
        "timestamp": time.Now().UTC(),
    }
    
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    
    return hub.Send(ctx, event)
}
```

#### Accounting Service (.NET) - Consumer
The accounting service needs to consume events from EventHub:

```csharp
// Add EventHub dependencies to Accounting.csproj
<PackageReference Include="Azure.Messaging.EventHubs" Version="5.10.0" />
<PackageReference Include="Azure.Messaging.EventHubs.Processor" Version="5.10.0" />

// EventHub consumer configuration
public class EventHubConsumerService : BackgroundService
{
    private readonly EventProcessorClient _processor;
    private readonly ILogger<EventHubConsumerService> _logger;

    public EventHubConsumerService(IConfiguration configuration, ILogger<EventHubConsumerService> logger)
    {
        _logger = logger;
        
        var connectionString = configuration["EVENTHUB_CONNECTION_STRING"];
        var eventHubName = configuration["EVENTHUB_NAME"];
        var consumerGroup = configuration["EVENTHUB_CONSUMER_GROUP"] ?? "accounting";

        if (!string.IsNullOrEmpty(connectionString))
        {
            _processor = new EventProcessorClient(
                new BlobContainerClient(configuration.GetConnectionString("Storage"), "eventhub-checkpoints"),
                consumerGroup,
                connectionString,
                eventHubName);

            _processor.ProcessEventAsync += ProcessEventHandler;
            _processor.ProcessErrorAsync += ProcessErrorHandler;
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (_processor != null)
        {
            _logger.LogInformation("Starting EventHub processor for accounting service");
            await _processor.StartProcessingAsync(stoppingToken);
        }
        else
        {
            _logger.LogWarning("EventHub not configured, using Kafka fallback");
            // Use existing Kafka consumer logic
        }
    }

    private async Task ProcessEventHandler(ProcessEventArgs eventArgs)
    {
        try
        {
            var eventData = eventArgs.Data.EventBody.ToArray();
            var orderEvent = JsonSerializer.Deserialize<OrderEvent>(eventData);
            
            // Process the accounting logic
            await ProcessAccountingEvent(orderEvent);
            
            // Update checkpoint
            await eventArgs.UpdateCheckpointAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing EventHub message");
        }
    }
}
```

#### Fraud Detection Service (Java) - Consumer
The fraud detection service needs to consume events from EventHub:

```java
// Add EventHub dependencies to build.gradle
implementation 'com.azure:azure-messaging-eventhubs:5.15.0'
implementation 'com.azure:azure-messaging-eventhubs-checkpointstore-blob:1.16.0'

// EventHub consumer configuration
@Service
public class EventHubConsumerService {
    
    private static final Logger logger = LoggerFactory.getLogger(EventHubConsumerService.class);
    
    @Value("${EVENTHUB_CONNECTION_STRING:}")
    private String connectionString;
    
    @Value("${EVENTHUB_NAME:otel-events}")
    private String eventHubName;
    
    @Value("${EVENTHUB_CONSUMER_GROUP:fraud-detection}")
    private String consumerGroup;
    
    private EventProcessorClient eventProcessorClient;
    
    @PostConstruct
    public void initialize() {
        if (!connectionString.isEmpty()) {
            BlobContainerAsyncClient blobContainerAsyncClient = new BlobContainerClientBuilder()
                .connectionString(System.getenv("AZURE_STORAGE_CONNECTION_STRING"))
                .containerName("eventhub-checkpoints")
                .buildAsyncClient();
            
            eventProcessorClient = new EventProcessorClientBuilder()
                .connectionString(connectionString, eventHubName)
                .consumerGroup(consumerGroup)
                .processEvent(this::processEvent)
                .processError(this::processError)
                .checkpointStore(new BlobCheckpointStore(blobContainerAsyncClient))
                .buildEventProcessorClient();
                
            eventProcessorClient.start();
            logger.info("Started EventHub processor for fraud detection");
        } else {
            logger.warn("EventHub not configured, using Kafka fallback");
            // Initialize Kafka consumer as fallback
        }
    }
    
    private void processEvent(EventContext eventContext) {
        try {
            EventData eventData = eventContext.getEventData();
            String eventBody = eventData.getBodyAsString();
            
            // Parse and process the order event for fraud detection
            OrderEvent orderEvent = objectMapper.readValue(eventBody, OrderEvent.class);
            processFraudDetection(orderEvent);
            
            // Checkpoint the event
            eventContext.updateCheckpoint();
            
        } catch (Exception e) {
            logger.error("Error processing EventHub event", e);
        }
    }
    
    private void processError(ErrorContext errorContext) {
        logger.error("Error in EventHub processing: {}", errorContext.getThrowable().getMessage());
    }
}
```

### Environment Variables Configuration

Each service needs these environment variables:

#### Checkout Service (Producer)
```bash
EVENTHUB_CONNECTION_STRING=Endpoint=sb://...
EVENTHUB_NAME=otel-events
KAFKA_ADDR=  # Empty to disable Kafka
```

#### Accounting Service (Consumer)
```bash
EVENTHUB_CONNECTION_STRING=Endpoint=sb://...
EVENTHUB_NAME=otel-events
EVENTHUB_CONSUMER_GROUP=accounting
KAFKA_ADDR=  # Empty to disable Kafka
```

#### Fraud Detection Service (Consumer)
```bash
EVENTHUB_CONNECTION_STRING=Endpoint=sb://...
EVENTHUB_NAME=otel-events
EVENTHUB_CONSUMER_GROUP=fraud-detection
KAFKA_ADDR=  # Empty to disable Kafka
```

### Message Format Compatibility

EventHub is Kafka-protocol compatible, so existing message formats should work. However, ensure:

1. **Message Keys**: Use partition keys for message distribution
2. **Headers**: EventHub supports message properties similar to Kafka headers
3. **Serialization**: JSON or Avro serialization works with both
4. **Error Handling**: Implement proper retry logic for EventHub-specific errors

### Monitoring EventHub Integration

```bash
# Check EventHub metrics in Azure Portal
az monitor metrics list \
  --resource "/subscriptions/{subscription}/resourceGroups/otel-demo-rg/providers/Microsoft.EventHub/namespaces/{namespace-name}" \
  --metric "IncomingMessages,OutgoingMessages"

# View consumer group lag
az eventhubs consumergroup show \
  --resource-group otel-demo-rg \
  --namespace-name {namespace-name} \
  --eventhub-name otel-events \
  --name accounting

# Check service logs for EventHub connectivity
kubectl logs -n otel-demo deployment/checkout | grep -i eventhub
kubectl logs -n otel-demo deployment/accounting | grep -i eventhub
kubectl logs -n otel-demo deployment/fraud-detection | grep -i eventhub
```

## Resource Costs

### Estimated Monthly Costs (East US 2)
- **AKS Cluster** (3 x Standard_D4s_v3): ~$400-500
- **EventHub Namespace** (Standard, 2 TU): ~$25-40
- **Log Analytics Workspace**: ~$20-50 (depends on data ingestion)
- **Application Insights**: ~$10-30 (depends on telemetry volume)
- **Azure Container Registry**: ~$5 (Basic tier)
- **Virtual Network**: ~$5
- **Key Vault**: ~$3

**Total Estimated Monthly Cost: ~$470-630**

*Note: Costs may vary based on usage patterns, data retention, and regional pricing.*

## Scaling Considerations

### Horizontal Scaling
- Increase `nodeCount` in parameters for more worker nodes
- Use Kubernetes Horizontal Pod Autoscaler (HPA) for automatic scaling
- Consider cluster autoscaler for dynamic node scaling

### Vertical Scaling
- Upgrade `nodeVmSize` to larger VM sizes for more resources
- Adjust resource requests and limits in Kubernetes manifests

### Performance Optimization
- Use Azure CNI for better network performance
- Enable Azure Monitor for containers for observability
- Consider premium storage for databases

## Security Features

1. **Managed Identity** - Passwordless authentication to Azure services
2. **Azure Key Vault** - Secure secrets management
3. **Network Security** - Virtual network isolation
4. **RBAC** - Role-based access control
5. **Azure Monitor** - Security monitoring and alerting

## Monitoring and Observability

The deployment includes comprehensive observability:

- **Traces**: Jaeger for distributed tracing
- **Metrics**: Prometheus + Grafana for metrics visualization
- **Logs**: OpenSearch for log aggregation
- **APM**: Application Insights for application performance monitoring
- **Infrastructure**: Azure Monitor for infrastructure monitoring

## Troubleshooting

### Common Issues
1. **Insufficient Permissions**: Ensure your Azure account has Contributor role
2. **Resource Quotas**: Check Azure subscription quotas for VMs and IPs
3. **Network Connectivity**: Verify virtual network and subnet configurations
4. **Pod Scheduling**: Check node resources and pod resource requests

### Debugging Commands
```bash
# Check cluster status
kubectl cluster-info

# Check node status
kubectl get nodes

# Check pod status
kubectl get pods -n otel-demo

# View pod logs
kubectl logs -n otel-demo <pod-name>

# Describe problematic resources
kubectl describe pod -n otel-demo <pod-name>
```

## Cleanup

To avoid ongoing charges, delete the resource group when done:

```bash
az group delete --name otel-demo-rg --yes --no-wait
```

## Customization

### Adding Custom Services
1. Add your service to the Kubernetes manifests
2. Update service discovery configurations
3. Configure OpenTelemetry instrumentation

### Integrating with Existing Infrastructure
- Modify network configurations to connect to existing VNets
- Update DNS settings for service discovery
- Configure hybrid monitoring scenarios

## Support

For issues and questions:
- [OpenTelemetry Demo GitHub Issues](https://github.com/open-telemetry/opentelemetry-demo/issues)
- [OpenTelemetry Community Slack](https://cloud-native.slack.com/archives/C03B4CWV4DA)
- [Azure Support](https://azure.microsoft.com/support/)
