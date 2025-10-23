#!/bin/bash

# EventHub Integration Configuration Script
# This script configures the OpenTelemetry demo services to use Azure EventHub

set -e

# Configuration
RESOURCE_GROUP="otel-demo-rg"
DEPLOYMENT_NAME="otel-demo-deployment"
NAMESPACE="otel-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "No active Kubernetes context"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get EventHub connection string
get_eventhub_connection_string() {
    log_info "Retrieving EventHub connection string..."
    
    # Get EventHub namespace name first
    local eventhub_namespace=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.eventHubNamespaceName.value' \
        --output tsv 2>/dev/null)
    
    if [[ -z "$eventhub_namespace" || "$eventhub_namespace" == "null" ]]; then
        log_error "Failed to retrieve EventHub namespace name"
        log_error "Make sure the infrastructure is deployed and EventHub is enabled"
        exit 1
    fi
    
    # Get the connection string from the EventHub authorization rule
    EVENTHUB_CONNECTION_STRING=$(az eventhubs authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$eventhub_namespace" \
        --authorization-rule-name "OtelDemoAccessPolicy" \
        --query primaryConnectionString \
        --output tsv 2>/dev/null)
    
    if [[ -z "$EVENTHUB_CONNECTION_STRING" || "$EVENTHUB_CONNECTION_STRING" == "null" ]]; then
        log_error "Failed to retrieve EventHub connection string"
        log_error "Make sure the EventHub authorization rule exists"
        exit 1
    fi
    
    log_success "EventHub connection string retrieved"
}

# Create Kubernetes secret
create_eventhub_secret() {
    log_info "Creating EventHub Kubernetes secret..."
    
    # Delete existing secret if it exists
    kubectl delete secret eventhub-secret -n "$NAMESPACE" --ignore-not-found=true
    
    # Create new secret
    kubectl create secret generic eventhub-secret \
        --from-literal=connection-string="$EVENTHUB_CONNECTION_STRING" \
        -n "$NAMESPACE"
    
    log_success "EventHub secret created"
}

# Configure checkout service (producer)
configure_checkout_service() {
    log_info "Configuring checkout service for EventHub..."
    
    kubectl patch deployment checkout -n "$NAMESPACE" --type='merge' --patch='
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "'$(date +%Y-%m-%dT%H:%M:%S%z)'"
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
    
    log_success "Checkout service configured for EventHub"
}

# Configure accounting service (consumer)
configure_accounting_service() {
    log_info "Configuring accounting service for EventHub..."
    
    kubectl patch deployment accounting -n "$NAMESPACE" --type='merge' --patch='
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "'$(date +%Y-%m-%dT%H:%M:%S%z)'"
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
    
    log_success "Accounting service configured for EventHub"
}

# Configure fraud detection service (consumer)
configure_fraud_detection_service() {
    log_info "Configuring fraud detection service for EventHub..."
    
    kubectl patch deployment fraud-detection -n "$NAMESPACE" --type='merge' --patch='
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "'$(date +%Y-%m-%dT%H:%M:%S%z)'"
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
    
    log_success "Fraud detection service configured for EventHub"
}

# Wait for deployments to be ready
wait_for_deployments() {
    log_info "Waiting for deployments to be ready..."
    
    local services=("checkout" "accounting" "fraud-detection")
    
    for service in "${services[@]}"; do
        log_info "Waiting for $service deployment..."
        kubectl rollout status deployment/$service -n "$NAMESPACE" --timeout=300s
    done
    
    log_success "All deployments are ready"
}

# Verify configuration
verify_configuration() {
    log_info "Verifying EventHub configuration..."
    
    local services=("checkout" "accounting" "fraud-detection")
    
    for service in "${services[@]}"; do
        log_info "Checking $service environment variables..."
        
        # Check if EVENTHUB_CONNECTION_STRING is set
        if kubectl exec -n "$NAMESPACE" deployment/$service -- printenv EVENTHUB_CONNECTION_STRING &>/dev/null; then
            log_success "$service: EventHub connection string is set"
        else
            log_error "$service: EventHub connection string not found"
        fi
        
        # Check if EVENTHUB_NAME is set
        local hub_name=$(kubectl exec -n "$NAMESPACE" deployment/$service -- printenv EVENTHUB_NAME 2>/dev/null || echo "")
        if [[ "$hub_name" == "otel-events" ]]; then
            log_success "$service: EventHub name is correct"
        else
            log_warning "$service: EventHub name is '$hub_name', expected 'otel-events'"
        fi
    done
}

# Show EventHub information
show_eventhub_info() {
    log_info "EventHub Information:"
    
    # Get EventHub details
    local eventhub_namespace=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.eventHubNamespaceName.value' \
        --output tsv 2>/dev/null)
    
    local eventhub_name=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs.eventHubName.value' \
        --output tsv 2>/dev/null)
    
    echo "  EventHub Namespace: $eventhub_namespace"
    echo "  EventHub Name: $eventhub_name"
    echo "  Consumer Groups: accounting, fraud-detection"
    echo ""
    
    log_info "To monitor EventHub metrics:"
    echo "  az monitor metrics list --resource \"/subscriptions/\$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$eventhub_namespace\" --metric \"IncomingMessages,OutgoingMessages\""
    echo ""
}

# Test EventHub connectivity
test_eventhub_connectivity() {
    log_info "Testing EventHub connectivity..."
    
    # Check service logs for EventHub-related messages
    local services=("checkout" "accounting" "fraud-detection")
    
    for service in "${services[@]}"; do
        log_info "Checking $service logs for EventHub messages..."
        
        # Get recent logs and look for EventHub-related entries
        local logs=$(kubectl logs -n "$NAMESPACE" deployment/$service --tail=50 --since=2m 2>/dev/null || echo "")
        
        if echo "$logs" | grep -qi "eventhub\|event.hub\|azure.messaging"; then
            log_success "$service: EventHub activity detected in logs"
        else
            log_warning "$service: No EventHub activity detected in recent logs"
        fi
    done
}

# Main function
main() {
    echo "=================================================="
    echo "EventHub Integration Configuration"
    echo "=================================================="
    echo ""
    
    check_prerequisites
    get_eventhub_connection_string
    create_eventhub_secret
    configure_checkout_service
    configure_accounting_service
    configure_fraud_detection_service
    wait_for_deployments
    verify_configuration
    show_eventhub_info
    test_eventhub_connectivity
    
    echo ""
    log_success "EventHub integration configuration completed!"
    echo ""
    echo "Next steps:"
    echo "1. Monitor the service logs to verify EventHub connectivity"
    echo "2. Test the application by placing orders through the frontend"
    echo "3. Check Azure Portal for EventHub metrics and message flow"
    echo "4. Verify that accounting and fraud detection services are processing events"
    echo ""
    echo "Monitoring commands:"
    echo "  kubectl logs -n $NAMESPACE deployment/checkout --follow"
    echo "  kubectl logs -n $NAMESPACE deployment/accounting --follow"
    echo "  kubectl logs -n $NAMESPACE deployment/fraud-detection --follow"
    echo ""
}

# Handle script arguments
case "${1:-}" in
    "verify")
        check_prerequisites
        verify_configuration
        ;;
    "test")
        check_prerequisites
        test_eventhub_connectivity
        ;;
    "")
        main
        ;;
    *)
        echo "Usage: $0 [verify|test]"
        echo "  verify - Only verify current configuration"
        echo "  test   - Test EventHub connectivity"
        echo "  (no args) - Full configuration setup"
        ;;
esac
