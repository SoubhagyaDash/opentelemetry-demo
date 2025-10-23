# Bicep Template Validation Script
# This script validates the Bicep template without deploying it

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "SouthCentralUS"
)

$BicepFile = "main.bicep"
$ParametersFile = "main.parameters.json"

Write-Host "Validating Bicep template..." -ForegroundColor Blue

# Check if files exist
if (-not (Test-Path $BicepFile)) {
    Write-Error "Bicep file '$BicepFile' not found."
    exit 1
}

if (-not (Test-Path $ParametersFile)) {
    Write-Error "Parameters file '$ParametersFile' not found."
    exit 1
}

# Create temporary resource group for validation if it doesn't exist
$existingRg = az group show --name $ResourceGroup 2>$null
if (-not $existingRg) {
    Write-Host "Creating temporary resource group for validation..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location
}

# Validate the deployment
Write-Host "Running Bicep validation..." -ForegroundColor Blue
az deployment group validate `
    --resource-group $ResourceGroup `
    --template-file $BicepFile `
    --parameters "@$ParametersFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Bicep template validation PASSED!" -ForegroundColor Green
} else {
    Write-Host "Bicep template validation FAILED!" -ForegroundColor Red
    exit 1
}

Write-Host "Validation completed successfully!" -ForegroundColor Green
