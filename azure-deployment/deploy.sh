#!/bin/bash

# OpenTelemetry Demo Azure Deployment Script
# This script automates the deployment of the OpenTelemetry demo on Azure Kubernetes Service

set -e

# Configuration
RESOURCE_GROUP="otel-demo-rg"
LOCATION="East US 2"
DEPLOYMENT_NAME="otel-demo-deployment"
BICEP_FILE="main.bicep"
PARAMETERS_FILE="main.parameters.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. You'll need it to manage the cluster."
    fi
    
    # Check if files exist
    if [[ ! -f "$BICEP_FILE" ]]; then
        log_error "Bicep file '$BICEP_FILE' not found."
        exit 1
    fi
    
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        log_error "Parameters file '$PARAMETERS_FILE' not found."
        exit 1
    fi
    
    log_success "Prerequisites check completed."
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists."
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        log_success "Resource group created successfully."
    fi
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Deploying infrastructure using Bicep template..."
    
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "$BICEP_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --verbose
    
    log_success "Infrastructure deployment completed."
}

# Get deployment outputs
get_deployment_outputs() {
    log_info "Retrieving deployment outputs..."
    
    # Get AKS cluster name
    AKS_CLUSTER_NAME=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.aksClusterName.value' \
        --output tsv)
    
    # Get ACR login server
    ACR_LOGIN_SERVER=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.acrLoginServer.value' \
        --output tsv)
    
    # Get other outputs
    KEY_VAULT_URI=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.keyVaultUri.value' \
        --output tsv)
    
    APP_INSIGHTS_KEY=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.appInsightsInstrumentationKey.value' \
        --output tsv)
    
    log_success "Deployment outputs retrieved."
    
    # Display information
    echo ""
    log_info "Deployment Information:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  AKS Cluster: $AKS_CLUSTER_NAME"
    echo "  ACR Login Server: $ACR_LOGIN_SERVER"
    echo "  Key Vault URI: $KEY_VAULT_URI"
    echo "  App Insights Key: $APP_INSIGHTS_KEY"
    echo ""
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl for AKS cluster..."
    
    if command -v kubectl &> /dev/null; then
        az aks get-credentials \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AKS_CLUSTER_NAME" \
            --overwrite-existing
        
        # Test connection
        if kubectl cluster-info &> /dev/null; then
            log_success "kubectl configured successfully."
        else
            log_error "Failed to connect to AKS cluster."
            exit 1
        fi
    else
        log_warning "kubectl not found. Please install kubectl and run:"
        echo "  az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME"
    fi
}

# Deploy OpenTelemetry demo
deploy_otel_demo() {
    log_info "Deploying OpenTelemetry demo application..."
    
    if command -v kubectl &> /dev/null; then
        # Check if Kubernetes manifest exists
        if [[ -f "../kubernetes/opentelemetry-demo.yaml" ]]; then
            kubectl apply -f "../kubernetes/opentelemetry-demo.yaml"
            log_success "OpenTelemetry demo deployed successfully."
        else
            log_warning "Kubernetes manifest not found. Please deploy manually using:"
            echo "  kubectl apply -f ../kubernetes/opentelemetry-demo.yaml"
        fi
    else
        log_warning "kubectl not available. Please deploy manually."
    fi
}

# Wait for deployment
wait_for_deployment() {
    log_info "Waiting for pods to be ready..."
    
    if command -v kubectl &> /dev/null; then
        # Wait for all pods to be ready (timeout after 10 minutes)
        kubectl wait --for=condition=Ready pods --all -n otel-demo --timeout=600s || {
            log_warning "Some pods may still be starting. Check status with: kubectl get pods -n otel-demo"
        }
        
        log_success "Deployment is ready."
    fi
}

# Show access information
show_access_info() {
    log_info "Getting service access information..."
    
    if command -v kubectl &> /dev/null; then
        echo ""
        echo "Service Access Information:"
        echo "=========================="
        
        # Get external IPs
        kubectl get services -n otel-demo --output wide
        
        echo ""
        echo "To access the application locally, use port forwarding:"
        echo "  kubectl port-forward -n otel-demo svc/frontend 8080:8080"
        echo ""
        echo "Then open: http://localhost:8080"
        echo ""
    fi
}

# Main deployment function
main() {
    echo "=========================================="
    echo "OpenTelemetry Demo Azure Deployment"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    create_resource_group
    deploy_infrastructure
    get_deployment_outputs
    configure_kubectl
    deploy_otel_demo
    wait_for_deployment
    show_access_info
    
    echo ""
    log_success "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Access the application using the information above"
    echo "2. Explore the observability features in Grafana, Jaeger, and Application Insights"
    echo "3. Generate some load using the built-in load generator"
    echo ""
    echo "To clean up resources when done:"
    echo "  az group delete --name $RESOURCE_GROUP --yes --no-wait"
    echo ""
}

# Handle script arguments
case "${1:-}" in
    "clean")
        log_info "Cleaning up resources..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        log_success "Cleanup initiated."
        ;;
    "status")
        if command -v kubectl &> /dev/null; then
            kubectl get all -n otel-demo
        else
            log_error "kubectl not available."
        fi
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [clean|status]"
        echo "  clean  - Delete all resources"
        echo "  status - Show deployment status"
        echo "  (no args) - Deploy everything"
        ;;
esac
