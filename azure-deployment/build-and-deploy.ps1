#!/usr/bin/env powershell
# Build and Deploy OpenTelemetry Demo from Source Code
# This script builds Docker images from your source code and deploys them to AKS

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-v1",
    
    [Parameter(Mandatory=$false)]
    [string]$AksClusterName = "otel-demo-aks-dev",
    
    [Parameter(Mandatory=$false)]
    [string]$AcrName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "otel-demo",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBuild,
    
    [Parameter(Mandatory=$false)]
    [switch]$BuildOnly,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Services = @()
)

# Color functions for output
function Write-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Define all services that can be built
$AllServices = @{
    "accounting" = @{
        "dockerfile" = "./src/accounting/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "ad" = @{
        "dockerfile" = "./src/ad/Dockerfile"
        "context" = "./"
        "enabled" = $true
        "buildArgs" = @{
            "OTEL_JAVA_AGENT_VERSION" = "2.20.1"
        }
    }
    "cart" = @{
        "dockerfile" = "./src/cart/src/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "checkout" = @{
        "dockerfile" = "./src/checkout/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "currency" = @{
        "dockerfile" = "./src/currency/Dockerfile"
        "context" = "./"
        "enabled" = $true
        "buildArgs" = @{
            "OPENTELEMETRY_CPP_VERSION" = "1.23.0"
        }
    }
    "email" = @{
        "dockerfile" = "./src/email/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "fraud-detection" = @{
        "dockerfile" = "./src/fraud-detection/Dockerfile"
        "context" = "./"
        "enabled" = $true
        "buildArgs" = @{
            "OTEL_JAVA_AGENT_VERSION" = "2.20.1"
        }
    }
    "frontend" = @{
        "dockerfile" = "./src/frontend/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "frontend-proxy" = @{
        "dockerfile" = "./src/frontend-proxy/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "image-provider" = @{
        "dockerfile" = "./src/image-provider/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "load-generator" = @{
        "dockerfile" = "./src/load-generator/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "payment" = @{
        "dockerfile" = "./src/payment/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "product-catalog" = @{
        "dockerfile" = "./src/product-catalog/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "quote" = @{
        "dockerfile" = "./src/quote/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "recommendation" = @{
        "dockerfile" = "./src/recommendation/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "shipping" = @{
        "dockerfile" = "./src/shipping/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
    "flagd-ui" = @{
        "dockerfile" = "./src/flagd-ui/Dockerfile"
        "context" = "./"
        "enabled" = $true
    }
}

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if Docker is running
    try {
        docker version > $null 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Docker is not running. Please start Docker Desktop."
            return $false
        }
    }
    catch {
        Write-Error "Docker is not installed or not running."
        return $false
    }
    
    # Check if kubectl is installed
    if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Error "kubectl is not installed."
        return $false
    }
    
    # Check if Azure CLI is installed and logged in
    if (!(Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is not installed."
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
        Write-Error "Error checking Azure login status."
        return $false
    }
    
    Write-Success "Prerequisites check completed."
    return $true
}

function Get-AcrConfiguration {
    Write-Info "Retrieving ACR configuration..."
    
    if ([string]::IsNullOrEmpty($script:AcrName)) {
        # Get ACR name from deployment outputs
        $acrLoginServer = "oteldemo5jsiyjacr.azurecr.io"
        
        
        if ([string]::IsNullOrEmpty($acrLoginServer)) {
            Write-Error "Could not retrieve ACR login server from deployment."
            return $false
        }
        
        $script:AcrName = $acrLoginServer.Split('.')[0]
        $script:AcrLoginServer = $acrLoginServer
    }
    else {
        $script:AcrLoginServer = "$script:AcrName.azurecr.io"
    }
    
    Write-Info "ACR Name: $script:AcrName"
    Write-Info "ACR Login Server: $script:AcrLoginServer"
    
    # Login to ACR
    Write-Info "Logging into ACR..."
    az acr login --name $script:AcrName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to ACR."
        return $false
    }
    
    Write-Success "ACR configuration completed."
    return $true
}

function Build-Service {
    param(
        [string]$ServiceName,
        [hashtable]$ServiceConfig
    )
    
    Write-Info "Building service: $ServiceName"
    
    $imageName = "$script:AcrLoginServer/otel-demo-$ServiceName"
    $fullImageName = "$imageName`:$ImageTag"
    
    # Build the Docker image
    $buildArgs = @(
        "build",
        "-t", $fullImageName,
        "-f", $ServiceConfig.dockerfile
    )
    
    # Add build arguments if they exist
    if ($ServiceConfig.ContainsKey("buildArgs")) {
        foreach ($key in $ServiceConfig.buildArgs.Keys) {
            $buildArgs += "--build-arg"
            $buildArgs += "$key=$($ServiceConfig.buildArgs[$key])"
        }
    }
    
    $buildArgs += $ServiceConfig.context
    
    Write-Info "Running: docker $($buildArgs -join ' ')"
    & docker @buildArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to build $ServiceName"
        return $false
    }
    
    # Push to ACR
    Write-Info "Pushing $ServiceName to ACR..."
    docker push $fullImageName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to push $ServiceName to ACR"
        return $false
    }
    
    Write-Success "Successfully built and pushed: $ServiceName"
    return $true
}

function Build-AllServices {
    Write-Info "Building Docker images for OpenTelemetry Demo services..."
    
    $servicesToBuild = if ($Services.Count -gt 0) { $Services } else { $AllServices.Keys }
    $successCount = 0
    $failureCount = 0
    
    foreach ($serviceName in $servicesToBuild) {
        if (-not $AllServices.ContainsKey($serviceName)) {
            Write-Warning "Unknown service: $serviceName. Skipping."
            continue
        }
        
        if (-not $AllServices[$serviceName].enabled) {
            Write-Info "Service $serviceName is disabled. Skipping."
            continue
        }
        
        Write-Info "Building service $($successCount + $failureCount + 1) of $($servicesToBuild.Count): $serviceName"
        
        if (Build-Service -ServiceName $serviceName -ServiceConfig $AllServices[$serviceName]) {
            $successCount++
        }
        else {
            $failureCount++
            if (-not $Force) {
                Write-Error "Build failed for $serviceName. Use -Force to continue with other services."
                return $false
            }
        }
    }
    
    Write-Info "Build Summary: $successCount successful, $failureCount failed"
    
    if ($failureCount -gt 0 -and -not $Force) {
        Write-Error "Some builds failed. Use -Force to ignore failures."
        return $false
    }
    
    Write-Success "Docker images build completed."
    return $true
}

function Deploy-ToAks {
    param(
        [string]$ResourceGroupName,
        [string]$ClusterName
    )
    
    Write-Info "Deploying to AKS with custom images..."
    
    # Get AKS credentials
    Write-Info "Getting AKS credentials..."
    az aks get-credentials --resource-group $ResourceGroupName --name $ClusterName --overwrite-existing
    
    # Test kubectl connection
    try {
        kubectl cluster-info --request-timeout=10s 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to connect to AKS cluster."
            return $false
        }
    }
    catch {
        Write-Error "Failed to connect to AKS cluster."
        return $false
    }
    
    # Create namespace
    kubectl create namespace $script:Namespace --dry-run=client -o yaml | kubectl apply -f -
    
    # Get EventHub namespace from deployment
    Write-Info "Retrieving EventHub namespace..."
    $EventHubNamespace = az deployment group show `
        --resource-group $ResourceGroupName `
        --name "main" `
        --query 'properties.outputs.eventHubNamespaceName.value' `
        --output tsv 2>$null
    
    if ([string]::IsNullOrEmpty($EventHubNamespace) -or $EventHubNamespace -eq "null") {
        Write-Warning "Could not retrieve EventHub namespace from deployment. Using default."
        $EventHubNamespace = "oteldemo5jsiy"
    }
    
    Write-Info "EventHub Namespace: $EventHubNamespace"
    
    # Use the existing Kubernetes manifest and patch it with ACR images
    Write-Info "Deploying using Kubernetes manifest with ACR images..."
    
    # Copy the original manifest
    $manifestPath = "kubernetes/opentelemetry-demo.yaml"
    $customManifestPath = "kubernetes/opentelemetry-demo-custom.yaml"
    Copy-Item $manifestPath $customManifestPath
    
    # Read the manifest content
    $manifestContent = Get-Content $customManifestPath -Raw
    
    # Replace default images with ACR images
    $imageReplacements = @{
        'ghcr.io/open-telemetry/demo:.*-accounting' = "$script:AcrLoginServer/otel-demo-accounting:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-adservice' = "$script:AcrLoginServer/otel-demo-ad:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-cartservice' = "$script:AcrLoginServer/otel-demo-cart:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-checkoutservice' = "$script:AcrLoginServer/otel-demo-checkout:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-currencyservice' = "$script:AcrLoginServer/otel-demo-currency:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-emailservice' = "$script:AcrLoginServer/otel-demo-email:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-fraud-detection' = "$script:AcrLoginServer/otel-demo-fraud-detection:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-frontend' = "$script:AcrLoginServer/otel-demo-frontend:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-frontendproxy' = "$script:AcrLoginServer/otel-demo-frontend-proxy:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-imageprovider' = "$script:AcrLoginServer/otel-demo-image-provider:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-loadgenerator' = "$script:AcrLoginServer/otel-demo-load-generator:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-paymentservice' = "$script:AcrLoginServer/otel-demo-payment:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-productcatalogservice' = "$script:AcrLoginServer/otel-demo-product-catalog:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-quoteservice' = "$script:AcrLoginServer/otel-demo-quote:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-recommendationservice' = "$script:AcrLoginServer/otel-demo-recommendation:$ImageTag"
        'ghcr.io/open-telemetry/demo:.*-shippingservice' = "$script:AcrLoginServer/otel-demo-shipping:$ImageTag"
    }
    
    foreach ($pattern in $imageReplacements.Keys) {
        $manifestContent = $manifestContent -replace $pattern, $imageReplacements[$pattern]
    }
    
    # Update EventHub configuration
    $manifestContent = $manifestContent -replace 'kafka:9092', "$EventHubNamespace.servicebus.windows.net:9093"
    
    # Remove Kafka components since we're using EventHub
    Write-Info "Removing Kafka components (using Azure EventHub instead)..."
    
    # Remove Kafka Service
    $manifestContent = $manifestContent -replace '(?s)---\s*# Source: opentelemetry-demo/templates/component\.yaml\s*apiVersion: v1\s*kind: Service\s*metadata:\s*name: kafka.*?(?=---)', ''
    
    # Remove Kafka Deployment  
    $manifestContent = $manifestContent -replace '(?s)---\s*# Source: opentelemetry-demo/templates/component\.yaml\s*apiVersion: apps/v1\s*kind: Deployment\s*metadata:\s*name: kafka.*?(?=---)', ''
    
    # Remove init containers that wait for Kafka since we're using EventHub
    Write-Info "Removing init containers that wait for Kafka..."
    # Remove the entire initContainers section with wait-for-kafka
    $manifestContent = $manifestContent -replace '(?s)\s*initContainers:\s*-\s*command:\s*-\s*sh\s*-\s*-c\s*-\s*until nc -z -v -w30 kafka 9092.*?name:\s*wait-for-kafka\s*', ''
    # Also remove any standalone wait-for-kafka containers
    $manifestContent = $manifestContent -replace '(?s)initContainers:\s*-.*?name:\s*wait-for-kafka.*?(?=\s*volumes:)', ''
    
    # Add pull secret to each deployment's spec
    $manifestContent = $manifestContent -replace '(\s+)spec:\s*\n(\s+)selector:', "`$1spec:`n`$1  imagePullSecrets:`n`$1  - name: acr-secret`n`$2selector:"
    
    # Write the modified manifest
    $manifestContent | Out-File -FilePath $customManifestPath -Encoding utf8
    
    # Apply the manifest
    kubectl apply -f $customManifestPath -n $script:Namespace
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Kubernetes deployment with ACR images completed successfully."
        
        # Remove any remaining Kafka resources that might have been created
        Write-Info "Cleaning up Kafka resources (using EventHub instead)..."
        kubectl delete deployment kafka -n $script:Namespace --ignore-not-found=true 2>$null
        kubectl delete service kafka -n $script:Namespace --ignore-not-found=true 2>$null
        
        # Clean up custom manifest
        Remove-Item $customManifestPath -Force -ErrorAction SilentlyContinue
        return $true
    }
    else {
        Write-Error "Kubernetes deployment failed."
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
    
    # Get frontend service for port forwarding
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
    Write-Host "🏗️  Build and Deploy OpenTelemetry Demo from Source" -ForegroundColor Magenta
    Write-Host "=================================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Change to project root directory
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Set-Location $projectRoot
    Write-Info "Working directory: $(Get-Location)"
    
    # Check prerequisites
    if (!(Test-Prerequisites)) {
        exit 1
    }
    
    # Get ACR configuration
    if (!(Get-AcrConfiguration)) {
        exit 1
    }
    
    # Build Docker images
    if (!$SkipBuild) {
        if (!(Build-AllServices)) {
            exit 1
        }
    }
    else {
        Write-Info "Skipping build phase."
    }
    
    # Deploy to AKS
    if (!$BuildOnly) {
        if (!(Deploy-ToAks -ResourceGroupName $ResourceGroup -ClusterName $AksClusterName)) {
            exit 1
        }
        
        # Show deployment status
        Show-DeploymentStatus
    }
    else {
        Write-Info "Build-only mode. Skipping deployment."
    }
    
    Write-Host ""
    Write-Success "🎉 Build and deployment completed successfully!"
    Write-Host ""
    Write-Info "Your custom OpenTelemetry Demo is now running on AKS!"
    Write-Info "All container images were built from your local source code."
    
} catch {
    Write-Error "Build and deployment failed with error: $_"
    exit 1
}