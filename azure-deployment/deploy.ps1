# OpenTelemetry Demo Azure Deployment - PowerShell Script
# This script automates the deployment of the OpenTelemetry demo on Azure Kubernetes Service

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("deploy", "clean", "status")]
    [string]$Action = "deploy",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-v1",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "SouthCentralUS",
    
    [Parameter(Mandatory=$false)]
    [string]$DeploymentName = "otel-demo-deployment",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "otel-demo"
)

# Configuration
$BicepFile = "main.bicep"
$ParametersFile = "main.parameters.json"

# Logging functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check Azure CLI
    try {
        $null = az version 2>$null
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if logged in to Azure
    try {
        $null = az account show 2>$null
    }
    catch {
        Write-Error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
    
    # Check kubectl
    try {
        $null = kubectl version --client 2>$null
    }
    catch {
        Write-Warning "kubectl is not installed. You'll need it to manage the cluster."
    }
    
    # Check if files exist
    if (-not (Test-Path $BicepFile)) {
        Write-Error "Bicep file '$BicepFile' not found."
        exit 1
    }
    
    if (-not (Test-Path $ParametersFile)) {
        Write-Error "Parameters file '$ParametersFile' not found."
        exit 1
    }
    
    Write-Success "Prerequisites check completed."
}

# Create resource group
function New-ResourceGroup {
    Write-Info "Creating resource group '$ResourceGroup' in '$Location'..."
    
    $existingRg = az group show --name $ResourceGroup 2>$null
    if ($existingRg) {
        Write-Warning "Resource group '$ResourceGroup' already exists."
    }
    else {
        az group create --name $ResourceGroup --location $Location
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Resource group created successfully."
        }
        else {
            Write-Error "Failed to create resource group."
            exit 1
        }
    }
}

# Deploy infrastructure
function Deploy-Infrastructure {
    Write-Info "Deploying infrastructure using Bicep template..."
    
    az deployment group create `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --template-file $BicepFile `
        --parameters "@$ParametersFile" `
        --verbose
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Infrastructure deployment completed."
    }
    else {
        Write-Error "Infrastructure deployment failed."
        exit 1
    }
}

# Get deployment outputs
function Get-DeploymentOutputs {
    Write-Info "Retrieving deployment outputs..."
    
    # Get AKS cluster name
    $script:AksClusterName = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.aksClusterName.value' `
        --output tsv
    
    # Get ACR login server
    $script:AcrLoginServer = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.acrLoginServer.value' `
        --output tsv
    
    # Get other outputs
    $script:KeyVaultUri = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.keyVaultUri.value' `
        --output tsv
    
    $script:AppInsightsKey = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.appInsightsInstrumentationKey.value' `
        --output tsv
    
    # Get EventHub outputs
    $script:EventHubNamespace = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubNamespaceName.value' `
        --output tsv
    
    $script:EventHubName = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubName.value' `
        --output tsv
    
    $script:EventHubConnectionString = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query 'properties.outputs.eventHubConnectionString.value' `
        --output tsv
    
    Write-Success "Deployment outputs retrieved."
    
    # Display information
    Write-Host ""
    Write-Info "Deployment Information:"
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Cyan
    Write-Host "  AKS Cluster: $script:AksClusterName" -ForegroundColor Cyan
    Write-Host "  ACR Login Server: $script:AcrLoginServer" -ForegroundColor Cyan
    Write-Host "  Key Vault URI: $script:KeyVaultUri" -ForegroundColor Cyan
    Write-Host "  App Insights Key: $script:AppInsightsKey" -ForegroundColor Cyan
    Write-Host "  EventHub Namespace: $script:EventHubNamespace" -ForegroundColor Cyan
    Write-Host "  EventHub Name: $script:EventHubName" -ForegroundColor Cyan
    Write-Host "  EventHub Connection String: [HIDDEN - Available in Key Vault]" -ForegroundColor Cyan
    Write-Host ""
}

# Configure kubectl
function Set-KubectlContext {
    Write-Info "Configuring kubectl for AKS cluster..."
    
    try {
        $null = kubectl version --client 2>$null
        
        az aks get-credentials `
            --resource-group $ResourceGroup `
            --name $script:AksClusterName `
            --overwrite-existing
        
        # Test connection
        $clusterInfo = kubectl cluster-info 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "kubectl configured successfully."
        }
        else {
            Write-Error "Failed to connect to AKS cluster."
            exit 1
        }
    }
    catch {
        Write-Warning "kubectl not found. Please install kubectl and run:"
        Write-Host "  az aks get-credentials --resource-group $ResourceGroup --name $script:AksClusterName" -ForegroundColor Yellow
    }
}

# Deploy OpenTelemetry demo
function Deploy-OtelDemo {
    Write-Info "Deploying OpenTelemetry demo application..."
    
    try {
        $null = kubectl version --client 2>$null
        
        # Check if Kubernetes manifest exists
        $manifestPath = "..\kubernetes\opentelemetry-demo.yaml"
        if (Test-Path $manifestPath) {
            # Create namespace if it doesn't exist
            kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
            # Apply the manifest to the specific namespace
            kubectl apply -f $manifestPath -n $Namespace
            if ($LASTEXITCODE -eq 0) {
                Write-Success "OpenTelemetry demo deployed successfully."
            }
            else {
                Write-Error "Failed to deploy OpenTelemetry demo."
            }
        }
        else {
            Write-Warning "Kubernetes manifest not found. Please deploy manually using:"
            Write-Host "  kubectl apply -f ..\kubernetes\opentelemetry-demo.yaml -n $Namespace" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "kubectl not available. Please deploy manually."
    }
}

# Wait for deployment
function Wait-ForDeployment {
    Write-Info "Waiting for pods to be ready..."
    
    try {
        $null = kubectl version --client 2>$null
        
        # Wait for all pods to be ready (timeout after 10 minutes)
        kubectl wait --for=condition=Ready pods --all -n otel-demo --timeout=600s
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Deployment is ready."
        }
        else {
            Write-Warning "Some pods may still be starting. Check status with: kubectl get pods -n otel-demo"
        }
    }
    catch {
        Write-Warning "kubectl not available to check pod status."
    }
}

# Show access information
function Show-AccessInfo {
    Write-Info "Getting service access information..."
    
    try {
        $null = kubectl version --client 2>$null
        
        Write-Host ""
        Write-Host "Service Access Information:" -ForegroundColor Magenta
        Write-Host "==========================" -ForegroundColor Magenta
        
        # Get external IPs
        kubectl get services -n otel-demo --output wide
        
        Write-Host ""
        Write-Host "To access the application locally, use port forwarding:" -ForegroundColor Cyan
        Write-Host "  kubectl port-forward -n otel-demo svc/frontend 8080:8080" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Then open: http://localhost:8080" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "kubectl not available to show service information."
    }
}

# Clean up resources
function Remove-Resources {
    Write-Info "Cleaning up resources..."
    
    $confirmation = Read-Host "Are you sure you want to delete resource group '$ResourceGroup'? (y/N)"
    if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
        az group delete --name $ResourceGroup --yes --no-wait
        Write-Success "Cleanup initiated."
    }
    else {
        Write-Info "Cleanup cancelled."
    }
}

# Show deployment status
function Show-Status {
    try {
        $null = kubectl version --client 2>$null
        kubectl get all -n otel-demo
    }
    catch {
        Write-Error "kubectl not available."
    }
}

# Main deployment function
function Start-MainDeployment {
    Write-Host "==========================================" -ForegroundColor Magenta
    Write-Host "OpenTelemetry Demo Azure Deployment" -ForegroundColor Magenta
    Write-Host "==========================================" -ForegroundColor Magenta
    Write-Host ""
    
    Test-Prerequisites
    New-ResourceGroup
    Deploy-Infrastructure
    Get-DeploymentOutputs
    Set-KubectlContext
    Deploy-OtelDemo
    Wait-ForDeployment
    Show-AccessInfo
    
    Write-Host ""
    Write-Success "Deployment completed successfully!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Configure EventHub integration by running: .\configure-eventhub.ps1"
    Write-Host "2. Access the application using the information above"
    Write-Host "3. Explore the observability features in Grafana, Jaeger, and Application Insights"
    Write-Host "4. Generate some load using the built-in load generator"
    Write-Host ""
    Write-Host "To clean up resources when done:" -ForegroundColor Yellow
    Write-Host "  .\deploy.ps1 -Action clean"
    Write-Host ""
}

# Main script execution
switch ($Action) {
    "deploy" {
        Start-MainDeployment
    }
    "clean" {
        Remove-Resources
    }
    "status" {
        Show-Status
    }
    default {
        Write-Host "Usage: .\deploy.ps1 -Action [deploy|clean|status]"
        Write-Host "  deploy - Deploy everything (default)"
        Write-Host "  clean  - Delete all resources"
        Write-Host "  status - Show deployment status"
    }
}
