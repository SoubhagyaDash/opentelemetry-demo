#!/usr/bin/env powershell
# Build OpenTelemetry Demo Docker Images
# This script builds all Docker images from your source code and pushes them to ACR

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "otel-demo-rg",
    
    [Parameter(Mandatory=$false)]
    [string]$AcrName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageTag = "latest",
    
    [Parameter(Mandatory=$false)]
    [string[]]$Services = @(),
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Color functions
function Write-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warning { param($msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# Main execution
Write-Host "🏗️  Building OpenTelemetry Demo Images" -ForegroundColor Magenta
Write-Host "=====================================" -ForegroundColor Magenta
Write-Host ""

if ($DryRun) {
    Write-Warning "DRY RUN MODE - No actual building will occur"
    Write-Host ""
}

# Change to project root
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Info "Project root: $(Get-Location)"
Write-Info "Services to build: $(if ($Services.Count -gt 0) { $Services -join ', ' } else { 'All services' })"
Write-Info "Image tag: $ImageTag"

if ($DryRun) {
    Write-Info "This would build and push Docker images to your ACR."
    Write-Info "Run without -DryRun to perform actual build."
} else {
    Write-Info "Starting build process..."
    Write-Warning "This will take 15-30 minutes depending on your machine."
    Write-Host ""
    
    # Call the main build script with BuildOnly flag
    $buildArgs = @(
        "-ResourceGroup", $ResourceGroup,
        "-ImageTag", $ImageTag,
        "-BuildOnly"
    )
    
    if (![string]::IsNullOrEmpty($AcrName)) {
        $buildArgs += @("-AcrName", $AcrName)
    }
    
    if ($Services.Count -gt 0) {
        $buildArgs += @("-Services", ($Services -join ','))
    }
    
    if ($Force) {
        $buildArgs += "-Force"
    }
    
    & "$PSScriptRoot\build-and-deploy.ps1" @buildArgs
}