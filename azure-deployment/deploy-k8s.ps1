#!/usr/bin/env powershell
# OpenTelemetry Demo AKS Deployment Script
# This script deploys the OpenTelemetry demo to AKS with Azure EventHub integration

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$AksClusterName = "otel-demo-aks-dev",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "otel-demo",
    
    [Parameter(Mandatory=$false)]
    [string]$EventHubNamespace = "",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipInfrastructure,
    
    [Parameter(Mandatory=$false)]
    [switch]$UsePreGeneratedManifest,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Color functions for output
function Write-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if kubectl is installed
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed. Please install kubectl first."
        return $false
    }
    
    # Check if helm is installed
    if (!(Get-Command helm -ErrorAction SilentlyContinue)) {
        Write-Error "Helm is not installed. Please install Helm first."
        Write-Info "Install with: winget install Helm.Helm"
        return $false
    }
    
    # Check if Azure CLI is installed and logged in
    if (!(Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is not installed. Please install Azure CLI first."
        return $false
    }
    
    try {
        $account = az account show --query "name" --output tsv 2>$null
        if ([string]::IsNullOrEmpty($account)) {
            Write-Error "Not logged into Azure. Please run 'az login' first."
            return $false
        }
        Write-Info "Logged into Azure as: $account"
    }
    catch {
        Write-Error "Error checking Azure login status: $_"
        return $false
    }
    
    Write-Success "Prerequisites check completed."
    return $true
}

function Get-AksCredentials {
    Write-Info "Getting AKS credentials..."
    
    try {
        az aks get-credentials --resource-group $ResourceGroup --name $AksClusterName --overwrite-existing
        
        # Test kubectl connection
        $clusterInfo = kubectl cluster-info --request-timeout=10s 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to connect to AKS cluster."
            return $false
        }
        
        Write-Success "Successfully connected to AKS cluster: $AksClusterName"
        return $true
    }
    catch {
        Write-Error "Failed to get AKS credentials: $_"
        return $false
    }
}

function Get-EventHubConfiguration {
    Write-Info "Retrieving EventHub configuration..."
    
    # Get EventHub namespace name if not provided
    if ([string]::IsNullOrEmpty($script:EventHubNamespace)) {
        $script:EventHubNamespace = az deployment group show `
            --resource-group $ResourceGroup `
            --name "main" `
            --query 'properties.outputs.eventHubNamespaceName.value' `
            --output tsv
    }
    
    # Get Key Vault name if not provided
    if ([string]::IsNullOrEmpty($script:KeyVaultName)) {
        $script:KeyVaultName = az deployment group show `
            --resource-group $ResourceGroup `
            --name "main" `
            --query 'properties.outputs.keyVaultUri.value' `
            --output tsv
        $script:KeyVaultName = $script:KeyVaultName -replace 'https://(.+)\.vault\.azure\.net/', '$1'
    }
    
    if ([string]::IsNullOrEmpty($script:EventHubNamespace)) {
        Write-Error "Could not retrieve EventHub namespace name."
        return $false
    }
    
    if ([string]::IsNullOrEmpty($script:KeyVaultName)) {
        Write-Error "Could not retrieve Key Vault name."
        return $false
    }
    
    Write-Info "EventHub Namespace: $script:EventHubNamespace"
    Write-Info "Key Vault: $script:KeyVaultName"
    
    # Get the EventHub connection string from Key Vault
    try {
        $script:EventHubConnectionString = az keyvault secret show `
            --vault-name $script:KeyVaultName `
            --name "EventHubConnectionString" `
            --query "value" `
            --output tsv
        
        if ([string]::IsNullOrEmpty($script:EventHubConnectionString)) {
            Write-Warning "EventHub connection string not found in Key Vault. Will try to retrieve directly."
            
            # Fallback: Get connection string directly from EventHub
            $script:EventHubConnectionString = az eventhubs eventhub authorization-rule keys list `
                --resource-group $ResourceGroup `
                --namespace-name $script:EventHubNamespace `
                --eventhub-name "otel-events" `
                --name "OtelDemoAccessPolicy" `
                --query "primaryConnectionString" `
                --output tsv
        }
        
        if ([string]::IsNullOrEmpty($script:EventHubConnectionString)) {
            Write-Error "Could not retrieve EventHub connection string."
            return $false
        }
        
        Write-Success "EventHub configuration retrieved successfully."
        return $true
    }
    catch {
        Write-Error "Failed to retrieve EventHub configuration: $_"
        return $false
    }
}

function Deploy-WithHelm {
    Write-Info "Deploying OpenTelemetry Demo using Helm..."
    
    # Add OpenTelemetry Helm repository
    Write-Info "Adding OpenTelemetry Helm repository..."
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
    helm repo update
    
    # Create namespace if it doesn't exist
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
    
    # Create EventHub secret
    Write-Info "Creating EventHub connection string secret..."
    kubectl create secret generic eventhub-secret `
        --namespace=$Namespace `
        --from-literal=connection-string="$script:EventHubConnectionString" `
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file for EventHub configuration
    $valuesContent = @"
opentelemetry-collector:
  config:
    exporters:
      kafka:
        brokers: ["$script:EventHubNamespace.servicebus.windows.net:9093"]
        protocol_version: "1.0.0"
        topic: "otel-events"
        auth:
          sasl:
            mechanism: "PLAIN"
            username: "`$ConnectionString"
            password: "$script:EventHubConnectionString"
        metadata:
          retry:
            max: 3
            backoff: 250ms

default:
  env:
    - name: KAFKA_SERVICE_ADDR
      value: "$script:EventHubNamespace.servicebus.windows.net:9093"
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
      value: "$script:EventHubNamespace.servicebus.windows.net:9093"
    - name: EVENTHUB_CONNECTION_STRING
      valueFrom:
        secretKeyRef:
          name: eventhub-secret
          key: connection-string

frauddetectionService:
  env:
    - name: KAFKA_SERVICE_ADDR
      value: "$script:EventHubNamespace.servicebus.windows.net:9093"
    - name: EVENTHUB_CONNECTION_STRING
      valueFrom:
        secretKeyRef:
          name: eventhub-secret
          key: connection-string
"@
    
    $valuesFile = "eventhub-values.yaml"
    $valuesContent | Out-File -FilePath $valuesFile -Encoding utf8
    
    # Deploy with Helm
    Write-Info "Installing OpenTelemetry Demo with EventHub configuration..."
    
    $helmArgs = @(
        "upgrade", "--install", "opentelemetry-demo",
        "open-telemetry/opentelemetry-demo",
        "--namespace", $Namespace,
        "--values", $valuesFile,
        "--timeout", "10m",
        "--wait"
    )
    
    if ($Force) {
        $helmArgs += "--force"
    }
    
    & helm @helmArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Helm deployment completed successfully."
        
        # Clean up values file
        Remove-Item $valuesFile -Force -ErrorAction SilentlyContinue
        
        return $true
    } else {
        Write-Error "Helm deployment failed."
        return $false
    }
}

function Deploy-WithManifest {
    Write-Info "Deploying OpenTelemetry Demo using pre-generated manifest..."
    
    # Apply the Kubernetes manifest
    kubectl apply -f "../kubernetes/opentelemetry-demo.yaml" -n $Namespace
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Kubernetes manifest applied successfully."
        Write-Warning "Note: You may need to manually configure EventHub integration in the deployed services."
        return $true
    } else {
        Write-Error "Failed to apply Kubernetes manifest."
        return $false
    }
}

function Show-DeploymentStatus {
    Write-Info "Checking deployment status..."
    
    Write-Host ""
    Write-Host "Pods in namespace '$Namespace':" -ForegroundColor Yellow
    kubectl get pods -n $Namespace
    
    Write-Host ""
    Write-Host "Services in namespace '$Namespace':" -ForegroundColor Yellow
    kubectl get services -n $Namespace
    
    Write-Host ""
    Write-Host "Ingresses in namespace '$Namespace':" -ForegroundColor Yellow
    kubectl get ingress -n $Namespace 2>$null
    
    # Try to get the frontend service URL
    $frontendService = kubectl get service -n $Namespace -l app.kubernetes.io/component=frontend -o jsonpath='{.items[0].metadata.name}' 2>$null
    
    if (![string]::IsNullOrEmpty($frontendService)) {
        Write-Host ""
        Write-Info "To access the application locally, run:"
        Write-Host "kubectl port-forward -n $Namespace service/$frontendService 8080:8080" -ForegroundColor Cyan
        Write-Host "Then visit: http://localhost:8080" -ForegroundColor Cyan
    }
}

# Main execution
try {
    Write-Host "🚀 OpenTelemetry Demo AKS Deployment" -ForegroundColor Magenta
    Write-Host "=====================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Check prerequisites
    if (!(Test-Prerequisites)) {
        exit 1
    }
    
    # Get AKS credentials
    if (!(Get-AksCredentials)) {
        exit 1
    }
    
    # Deploy based on selected method
    if ($UsePreGeneratedManifest) {
        # Use the existing Kubernetes manifest
        if (!(Deploy-WithManifest)) {
            exit 1
        }
    } else {
        # Use Helm with EventHub configuration
        if (!$SkipInfrastructure) {
            if (!(Get-EventHubConfiguration)) {
                exit 1
            }
        }
        
        if (!(Deploy-WithHelm)) {
            exit 1
        }
    }
    
    # Show deployment status
    Show-DeploymentStatus
    
    Write-Host ""
    Write-Success "🎉 OpenTelemetry Demo deployment completed successfully!"
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "1. Wait for all pods to be in 'Running' state" -ForegroundColor White
    Write-Host "2. Use port-forwarding to access the application locally" -ForegroundColor White
    Write-Host "3. Visit the application at http://localhost:8080" -ForegroundColor White
    Write-Host "4. Check telemetry data in your Azure monitoring tools" -ForegroundColor White
    
} catch {
    Write-Error "Deployment failed with error: $_"
    exit 1
}