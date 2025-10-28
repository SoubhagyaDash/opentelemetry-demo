# Deploying OpenTelemetry Demo to AKS

You have several deployment options for getting the OpenTelemetry demo running on your AKS cluster. Here are the recommended approaches:

## Option 1: Using the Official Helm Chart (Recommended)

This is the most flexible and configurable approach.

### Prerequisites
```powershell
# Install Helm if not already installed
winget install Helm.Helm

# Get AKS credentials
az aks get-credentials --resource-group otel-demo-rg --name otel-demo-aks-dev
```

### Deploy using Helm
```powershell
# Add the OpenTelemetry Helm repository
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# Create namespace
kubectl create namespace otel-demo

# Deploy with EventHub configuration
helm install opentelemetry-demo open-telemetry/opentelemetry-demo \
    --namespace otel-demo \
    --set opentelemetry-collector.config.exporters.kafka.brokers[0]="YOUR_EVENTHUB_NAMESPACE.servicebus.windows.net:9093" \
    --set opentelemetry-collector.config.exporters.kafka.protocol_version="1.0.0" \
    --set opentelemetry-collector.config.exporters.kafka.auth.sasl.mechanism="PLAIN" \
    --set opentelemetry-collector.config.exporters.kafka.auth.sasl.username="\$ConnectionString" \
    --set opentelemetry-collector.config.exporters.kafka.auth.sasl.password="YOUR_EVENTHUB_CONNECTION_STRING"
```

## Option 2: Using the Pre-generated Kubernetes Manifests

This uses the existing `kubernetes/opentelemetry-demo.yaml` file.

### Quick Deploy
```powershell
# Get AKS credentials
az aks get-credentials --resource-group otel-demo-rg --name otel-demo-aks-dev

# Deploy the manifest
kubectl apply -f kubernetes/opentelemetry-demo.yaml
```

### Modify for EventHub
The manifest needs to be updated to replace Kafka with EventHub configuration.

## Option 3: Custom Deployment with EventHub Integration (Recommended for Azure)

Let me create a custom deployment script that properly configures EventHub:

```powershell
# This approach creates a customized values.yaml file for EventHub
```

## Recommended Approach: Custom Helm Deployment

Since you're using Azure EventHub instead of Kafka, I'll create a custom deployment script that:

1. Configures the OpenTelemetry Collector to use EventHub
2. Sets up proper authentication using the connection string from Key Vault
3. Configures all services to send telemetry to EventHub

Would you like me to create this custom deployment script? It will:

- Use Helm for deployment flexibility
- Automatically retrieve EventHub connection strings from your Key Vault
- Configure all services for Azure EventHub
- Set up proper monitoring and observability

## Next Steps

1. **Choose your deployment method** (I recommend the custom Helm approach)
2. **Run the EventHub configuration script** we created earlier
3. **Deploy the application** using your chosen method
4. **Verify the deployment** and test the application

Let me know which approach you'd prefer, and I can create the specific deployment scripts and configurations for your setup!