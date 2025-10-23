# EventHub Integration Configuration Script - PowerShell
# This script configures the OpenTelemetry demo services to use Azure EventHub

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("configure", "verify", "test")]
    [string]$Action = "configure",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "otel-demo-deployment",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "otel-demo"
)

# Logging functions
function Write-Info { param([string]$Message); Write-Host "[INFO] $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message); Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Warning { param([string]$Message); Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param([string]$Message); Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    try { $null = az version 2>$null }
    catch { Write-Error "Azure CLI not found"; exit 1 }
    
    try { $null = kubectl version --client 2>$null }
    catch { Write-Error "kubectl not found"; exit 1 }
    
    try { $null = kubectl cluster-info 2>$null }
    catch { Write-Error "No active Kubernetes context"; exit 1 }
    
    Write-Success "Prerequisites check passed"
}

# Get EventHub connection string
function Get-EventHubConnectionString {
    Write-Info "Retrieving EventHub connection string..."
    
    # Get EventHub namespace name first
    $eventHubNamespace = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubNamespaceName.value' `
        --output tsv 2>$null
    
    if ([string]::IsNullOrEmpty($eventHubNamespace) -or $eventHubNamespace -eq "null") {
        Write-Error "Failed to retrieve EventHub namespace name"
        Write-Error "Make sure the infrastructure is deployed and EventHub is enabled"
        exit 1
    }
    
    # Get the connection string from the EventHub authorization rule
    $script:EventHubConnectionString = az eventhubs authorization-rule keys list `
        --resource-group $ResourceGroup `
        --namespace-name $eventHubNamespace `
        --authorization-rule-name "OtelDemoAccessPolicy" `
        --query primaryConnectionString `
        --output tsv 2>$null
    
    if ([string]::IsNullOrEmpty($script:EventHubConnectionString) -or $script:EventHubConnectionString -eq "null") {
        Write-Error "Failed to retrieve EventHub connection string"
        Write-Error "Make sure the EventHub authorization rule exists"
        exit 1
    }
    
    Write-Success "EventHub connection string retrieved"
}

# Create Kubernetes secret
function New-EventHubSecret {
    Write-Info "Creating EventHub Kubernetes secret..."
    
    # Delete existing secret if it exists
    kubectl delete secret eventhub-secret -n $Namespace --ignore-not-found=true 2>$null
    
    # Create new secret
    kubectl create secret generic eventhub-secret `
        --from-literal=connection-string="$script:EventHubConnectionString" `
        -n $Namespace
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "EventHub secret created"
    } else {
        Write-Error "Failed to create EventHub secret"
        exit 1
    }
}

# Configure checkout service (producer)
function Set-CheckoutServiceConfig {
    Write-Info "Configuring checkout service for EventHub..."
    
    $timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $patch = @"
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "$timestamp"
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
          value: "true"
"@
    
    $patch | kubectl patch deployment checkout -n $Namespace --type='merge' --patch-file=-
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Checkout service configured for EventHub"
    } else {
        Write-Error "Failed to configure checkout service"
    }
}

# Configure accounting service (consumer)
function Set-AccountingServiceConfig {
    Write-Info "Configuring accounting service for EventHub..."
    
    $timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $patch = @"
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "$timestamp"
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
          value: "true"
"@
    
    $patch | kubectl patch deployment accounting -n $Namespace --type='merge' --patch-file=-
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Accounting service configured for EventHub"
    } else {
        Write-Error "Failed to configure accounting service"
    }
}

# Configure fraud detection service (consumer)
function Set-FraudDetectionServiceConfig {
    Write-Info "Configuring fraud detection service for EventHub..."
    
    $timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $patch = @"
spec:
  template:
    metadata:
      annotations:
        kubectl.kubernetes.io/restartedAt: "$timestamp"
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
          value: "true"
"@
    
    $patch | kubectl patch deployment fraud-detection -n $Namespace --type='merge' --patch-file=-
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Fraud detection service configured for EventHub"
    } else {
        Write-Error "Failed to configure fraud detection service"
    }
}

# Wait for deployments to be ready
function Wait-ForDeployments {
    Write-Info "Waiting for deployments to be ready..."
    
    $services = @("checkout", "accounting", "fraud-detection")
    
    foreach ($service in $services) {
        Write-Info "Waiting for $service deployment..."
        kubectl rollout status deployment/$service -n $Namespace --timeout=300s
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Timeout waiting for $service deployment"
        }
    }
    
    Write-Success "Deployment rollouts completed"
}

# Verify configuration
function Test-Configuration {
    Write-Info "Verifying EventHub configuration..."
    
    $services = @("checkout", "accounting", "fraud-detection")
    
    foreach ($service in $services) {
        Write-Info "Checking $service environment variables..."
        
        # Check if EVENTHUB_CONNECTION_STRING is set
        try {
            $null = kubectl exec -n $Namespace deployment/$service -- printenv EVENTHUB_CONNECTION_STRING 2>$null
            Write-Success "$service`: EventHub connection string is set"
        }
        catch {
            Write-Error "$service`: EventHub connection string not found"
        }
        
        # Check if EVENTHUB_NAME is set
        try {
            $hubName = kubectl exec -n $Namespace deployment/$service -- printenv EVENTHUB_NAME 2>$null
            if ($hubName -eq "otel-events") {
                Write-Success "$service`: EventHub name is correct"
            } else {
                Write-Warning "$service`: EventHub name is '$hubName', expected 'otel-events'"
            }
        }
        catch {
            Write-Warning "$service`: EventHub name not set"
        }
    }
}

# Show EventHub information
function Show-EventHubInfo {
    Write-Info "EventHub Information:"
    
    # Get EventHub details
    $eventHubNamespace = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubNamespaceName.value' `
        --output tsv 2>$null
    
    $eventHubName = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubName.value' `
        --output tsv 2>$null
    
    Write-Host "  EventHub Namespace: $eventHubNamespace" -ForegroundColor Cyan
    Write-Host "  EventHub Name: $eventHubName" -ForegroundColor Cyan
    Write-Host "  Consumer Groups: accounting, fraud-detection" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Info "To monitor EventHub metrics:"
    $subscriptionId = az account show --query id -o tsv
    Write-Host "  az monitor metrics list --resource `"/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubNamespace`" --metric `"IncomingMessages,OutgoingMessages`"" -ForegroundColor Yellow
    Write-Host ""
}

# Test EventHub connectivity
function Test-EventHubConnectivity {
    Write-Info "Testing EventHub connectivity..."
    
    $services = @("checkout", "accounting", "fraud-detection")
    
    foreach ($service in $services) {
        Write-Info "Checking $service logs for EventHub messages..."
        
        try {
            $logs = kubectl logs -n $Namespace deployment/$service --tail=50 --since=2m 2>$null
            
            if ($logs -match "eventhub|event.hub|azure.messaging") {
                Write-Success "$service`: EventHub activity detected in logs"
            } else {
                Write-Warning "$service`: No EventHub activity detected in recent logs"
            }
        }
        catch {
            Write-Warning "$service`: Unable to retrieve logs"
        }
    }
}

# Main configuration function
function Start-EventHubConfiguration {
    Write-Host "==================================================" -ForegroundColor Magenta
    Write-Host "EventHub Integration Configuration" -ForegroundColor Magenta
    Write-Host "==================================================" -ForegroundColor Magenta
    Write-Host ""
    
    Test-Prerequisites
    Get-EventHubConnectionString
    New-EventHubSecret
    Set-CheckoutServiceConfig
    Set-AccountingServiceConfig
    Set-FraudDetectionServiceConfig
    Wait-ForDeployments
    Test-Configuration
    Show-EventHubInfo
    Test-EventHubConnectivity
    
    Write-Host ""
    Write-Success "EventHub integration configuration completed!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Monitor the service logs to verify EventHub connectivity"
    Write-Host "2. Test the application by placing orders through the frontend"
    Write-Host "3. Check Azure Portal for EventHub metrics and message flow"
    Write-Host "4. Verify that accounting and fraud detection services are processing events"
    Write-Host ""
    Write-Host "Monitoring commands:" -ForegroundColor Yellow
    Write-Host "  kubectl logs -n $Namespace deployment/checkout --follow"
    Write-Host "  kubectl logs -n $Namespace deployment/accounting --follow"
    Write-Host "  kubectl logs -n $Namespace deployment/fraud-detection --follow"
    Write-Host ""
}

# Main script execution
switch ($Action) {
    "configure" {
        Start-EventHubConfiguration
    }
    "verify" {
        Test-Prerequisites
        Test-Configuration
    }
    "test" {
        Test-Prerequisites
        Test-EventHubConnectivity
    }
    default {
        Write-Host "Usage: .\configure-eventhub.ps1 -Action [configure|verify|test]"
        Write-Host "  configure - Full configuration setup (default)"
        Write-Host "  verify    - Only verify current configuration"
        Write-Host "  test      - Test EventHub connectivity"
    }
}
