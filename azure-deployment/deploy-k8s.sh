#!/bin/bash
# OpenTelemetry Demo AKS Deployment Script
# This script deploys the OpenTelemetry demo to AKS with Azure EventHub integration

set -euo pipefail

# Default values
RESOURCE_GROUP="${RESOURCE_GROUP:-otel-demo-rg}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-otel-demo-aks-dev}"
NAMESPACE="${NAMESPACE:-otel-demo}"
SKIP_INFRASTRUCTURE="${SKIP_INFRASTRUCTURE:-false}"
USE_MANIFEST="${USE_MANIFEST:-false}"
FORCE="${FORCE:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info() { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed. Please install Helm first."
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    local account=$(az account show --query "name" --output tsv)
    info "Logged into Azure as: $account"
    
    success "Prerequisites check completed."
}

get_aks_credentials() {
    info "Getting AKS credentials..."
    
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" --overwrite-existing
    
    # Test kubectl connection
    if ! kubectl cluster-info --request-timeout=10s &> /dev/null; then
        error "Failed to connect to AKS cluster."
        exit 1
    fi
    
    success "Successfully connected to AKS cluster: $AKS_CLUSTER_NAME"
}

get_eventhub_configuration() {
    info "Retrieving EventHub configuration..."
    
    # Get EventHub namespace name
    EVENTHUB_NAMESPACE=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "main" \
        --query 'properties.outputs.eventHubNamespaceName.value' \
        --output tsv)
    
    # Get Key Vault name
    KEYVAULT_URI=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "main" \
        --query 'properties.outputs.keyVaultUri.value' \
        --output tsv)
    KEYVAULT_NAME=$(echo "$KEYVAULT_URI" | sed 's|https://\(.*\)\.vault\.azure\.net/|\1|')
    
    if [[ -z "$EVENTHUB_NAMESPACE" ]]; then
        error "Could not retrieve EventHub namespace name."
        exit 1
    fi
    
    if [[ -z "$KEYVAULT_NAME" ]]; then
        error "Could not retrieve Key Vault name."
        exit 1
    fi
    
    info "EventHub Namespace: $EVENTHUB_NAMESPACE"
    info "Key Vault: $KEYVAULT_NAME"
    
    # Get the EventHub connection string from Key Vault
    EVENTHUB_CONNECTION_STRING=$(az keyvault secret show \
        --vault-name "$KEYVAULT_NAME" \
        --name "EventHubConnectionString" \
        --query "value" \
        --output tsv 2>/dev/null || true)
    
    if [[ -z "$EVENTHUB_CONNECTION_STRING" ]]; then
        warning "EventHub connection string not found in Key Vault. Trying direct access..."
        
        # Fallback: Get connection string directly from EventHub
        EVENTHUB_CONNECTION_STRING=$(az eventhubs eventhub authorization-rule keys list \
            --resource-group "$RESOURCE_GROUP" \
            --namespace-name "$EVENTHUB_NAMESPACE" \
            --eventhub-name "otel-events" \
            --name "OtelDemoAccessPolicy" \
            --query "primaryConnectionString" \
            --output tsv)
    fi
    
    if [[ -z "$EVENTHUB_CONNECTION_STRING" ]]; then
        error "Could not retrieve EventHub connection string."
        exit 1
    fi
    
    success "EventHub configuration retrieved successfully."
}

deploy_with_helm() {
    info "Deploying OpenTelemetry Demo using Helm..."
    
    # Add OpenTelemetry Helm repository
    info "Adding OpenTelemetry Helm repository..."
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo update
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Create EventHub secret
    info "Creating EventHub connection string secret..."
    kubectl create secret generic eventhub-secret \
        --namespace="$NAMESPACE" \
        --from-literal=connection-string="$EVENTHUB_CONNECTION_STRING" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file for EventHub configuration
    cat > eventhub-values.yaml << EOF
opentelemetry-collector:
  config:
    exporters:
      kafka:
        brokers: ["$EVENTHUB_NAMESPACE.servicebus.windows.net:9093"]
        protocol_version: "1.0.0"
        topic: "otel-events"
        auth:
          sasl:
            mechanism: "PLAIN"
            username: "\$ConnectionString"
            password: "$EVENTHUB_CONNECTION_STRING"
        metadata:
          retry:
            max: 3
            backoff: 250ms

default:
  env:
    - name: KAFKA_SERVICE_ADDR
      value: "$EVENTHUB_NAMESPACE.servicebus.windows.net:9093"
    - name: EVENTHUB_CONNECTION_STRING
      valueFrom:
        secretKeyRef:
          name: eventhub-secret
          key: connection-string

# Disable Kafka since we're using EventHub
kafka:
  enabled: false

# Configure services for EventHub
accountingService:
  env:
    - name: KAFKA_SERVICE_ADDR
      value: "$EVENTHUB_NAMESPACE.servicebus.windows.net:9093"
    - name: EVENTHUB_CONNECTION_STRING
      valueFrom:
        secretKeyRef:
          name: eventhub-secret
          key: connection-string

frauddetectionService:
  env:
    - name: KAFKA_SERVICE_ADDR
      value: "$EVENTHUB_NAMESPACE.servicebus.windows.net:9093"
    - name: EVENTHUB_CONNECTION_STRING
      valueFrom:
        secretKeyRef:
          name: eventhub-secret
          key: connection-string
EOF
    
    # Deploy with Helm
    info "Installing OpenTelemetry Demo with EventHub configuration..."
    
    local helm_args=(
        "upgrade" "--install" "opentelemetry-demo"
        "open-telemetry/opentelemetry-demo"
        "--namespace" "$NAMESPACE"
        "--values" "eventhub-values.yaml"
        "--timeout" "10m"
        "--wait"
    )
    
    if [[ "$FORCE" == "true" ]]; then
        helm_args+=("--force")
    fi
    
    if helm "${helm_args[@]}"; then
        success "Helm deployment completed successfully."
        rm -f eventhub-values.yaml
    else
        error "Helm deployment failed."
        exit 1
    fi
}

deploy_with_manifest() {
    info "Deploying OpenTelemetry Demo using pre-generated manifest..."
    
    kubectl apply -f "../kubernetes/opentelemetry-demo.yaml" -n "$NAMESPACE"
    
    success "Kubernetes manifest applied successfully."
    warning "Note: You may need to manually configure EventHub integration in the deployed services."
}

show_deployment_status() {
    info "Checking deployment status..."
    
    echo ""
    echo -e "${YELLOW}Pods in namespace '$NAMESPACE':${NC}"
    kubectl get pods -n "$NAMESPACE"
    
    echo ""
    echo -e "${YELLOW}Services in namespace '$NAMESPACE':${NC}"
    kubectl get services -n "$NAMESPACE"
    
    echo ""
    echo -e "${YELLOW}Ingresses in namespace '$NAMESPACE':${NC}"
    kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "No ingresses found"
    
    # Try to get the frontend service URL
    local frontend_service=$(kubectl get service -n "$NAMESPACE" -l app.kubernetes.io/component=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    
    if [[ -n "$frontend_service" ]]; then
        echo ""
        info "To access the application locally, run:"
        echo -e "${CYAN}kubectl port-forward -n $NAMESPACE service/$frontend_service 8080:8080${NC}"
        echo -e "${CYAN}Then visit: http://localhost:8080${NC}"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --cluster-name)
            AKS_CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-infrastructure)
            SKIP_INFRASTRUCTURE="true"
            shift
            ;;
        --use-manifest)
            USE_MANIFEST="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --resource-group NAME     Azure resource group (default: otel-demo-rg)"
            echo "  --cluster-name NAME       AKS cluster name (default: otel-demo-aks-dev)"
            echo "  --namespace NAME          Kubernetes namespace (default: otel-demo)"
            echo "  --skip-infrastructure     Skip EventHub configuration retrieval"
            echo "  --use-manifest           Use pre-generated manifest instead of Helm"
            echo "  --force                  Force Helm deployment"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main execution
echo -e "${BLUE}🚀 OpenTelemetry Demo AKS Deployment${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check prerequisites
check_prerequisites

# Get AKS credentials
get_aks_credentials

# Deploy based on selected method
if [[ "$USE_MANIFEST" == "true" ]]; then
    # Use the existing Kubernetes manifest
    deploy_with_manifest
else
    # Use Helm with EventHub configuration
    if [[ "$SKIP_INFRASTRUCTURE" != "true" ]]; then
        get_eventhub_configuration
    fi
    
    deploy_with_helm
fi

# Show deployment status
show_deployment_status

echo ""
success "🎉 OpenTelemetry Demo deployment completed successfully!"
echo ""
info "Next steps:"
echo "1. Wait for all pods to be in 'Running' state"
echo "2. Use port-forwarding to access the application locally"
echo "3. Visit the application at http://localhost:8080"
echo "4. Check telemetry data in your Azure monitoring tools"