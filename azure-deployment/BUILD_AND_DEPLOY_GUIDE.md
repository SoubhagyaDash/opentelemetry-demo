# Building and Deploying Your Source Code to AKS

## 🎯 Overview

I've created scripts to build your OpenTelemetry Demo source code into Docker images and deploy them to your AKS cluster.

## 📋 Prerequisites

Before running the build scripts, ensure you have:

- ✅ **Docker Desktop** running
- ✅ **Azure CLI** logged in (`az login`)
- ✅ **Infrastructure deployed** (run `.\deploy.ps1` first)
- ✅ **kubectl** configured for your AKS cluster

## 🚀 Quick Start

### Option 1: Build and Deploy Everything
```powershell
# Build all services and deploy to AKS
.\build-and-deploy.ps1
```

### Option 2: Build Only (No Deployment)
```powershell
# Just build and push images to ACR
.\build-images.ps1
```

### Option 3: Deploy Pre-built Images
```powershell
# If images are already built, just deploy
.\build-and-deploy.ps1 -SkipBuild
```

## 🛠️ Advanced Usage

### Build Specific Services
```powershell
# Build only frontend and checkout services
.\build-and-deploy.ps1 -Services @("frontend", "checkout")
```

### Custom Image Tag
```powershell
# Use a specific tag for your images
.\build-and-deploy.ps1 -ImageTag "v1.0.0"
```

### Force Rebuild
```powershell
# Force rebuild even if some services fail
.\build-and-deploy.ps1 -Force
```

### Dry Run
```powershell
# See what would be built without actually building
.\build-images.ps1 -DryRun
```

## 📦 What Gets Built

The script will build Docker images for these services from your source code:

| Service | Source Directory | Technology |
|---------|------------------|------------|
| **accounting** | `src/accounting/` | .NET |
| **ad** | `src/ad/` | Java |
| **cart** | `src/cart/` | .NET |
| **checkout** | `src/checkout/` | Go |
| **currency** | `src/currency/` | C++ |
| **email** | `src/email/` | Ruby |
| **fraud-detection** | `src/fraud-detection/` | Kotlin |
| **frontend** | `src/frontend/` | Next.js |
| **frontend-proxy** | `src/frontend-proxy/` | Envoy |
| **image-provider** | `src/image-provider/` | Nginx |
| **load-generator** | `src/load-generator/` | Python |
| **payment** | `src/payment/` | Node.js |
| **product-catalog** | `src/product-catalog/` | Go |
| **quote** | `src/quote/` | PHP |
| **recommendation** | `src/recommendation/` | Python |
| **shipping** | `src/shipping/` | Rust |
| **flagd-ui** | `src/flagd-ui/` | Elixir |

## 🔄 Build Process

1. **Source Code** → **Docker Build** → **Push to ACR** → **Deploy to AKS**

Each service will be:
1. Built from its Dockerfile in the `src/` directory
2. Tagged as `{your-acr}.azurecr.io/otel-demo-{service}:latest`
3. Pushed to your Azure Container Registry
4. Deployed to AKS using Helm with custom image references

## ⏱️ Expected Build Times

- **All services**: 15-30 minutes (depending on your machine)
- **Single service**: 1-3 minutes
- **Deployment**: 5-10 minutes

## 🔍 Monitoring Progress

The scripts provide detailed output:
```
[INFO] Building service: frontend
[INFO] Running: docker build -t youracr.azurecr.io/otel-demo-frontend:latest -f ./src/frontend/Dockerfile ./
[SUCCESS] Successfully built and pushed: frontend
```

## 🚨 Troubleshooting

### Common Issues

**Docker not running:**
```
[ERROR] Docker is not running. Please start Docker Desktop.
```
→ Start Docker Desktop and wait for it to be ready

**ACR login fails:**
```
[ERROR] Failed to login to ACR.
```
→ Check Azure CLI login: `az login`

**Build fails:**
```
[ERROR] Failed to build frontend
```
→ Use `-Force` to continue with other services, or fix the specific service

**Out of disk space:**
```
no space left on device
```
→ Clean up Docker images: `docker system prune -a`

### Getting Help

**Check what would be built:**
```powershell
.\build-images.ps1 -DryRun
```

**Build just one service to test:**
```powershell
.\build-and-deploy.ps1 -Services @("frontend") -BuildOnly
```

**Check deployment status:**
```powershell
kubectl get pods -n otel-demo
kubectl logs -n otel-demo deployment/frontend
```

## 🎉 Success!

After successful deployment, you'll see:
```
[SUCCESS] 🎉 Build and deployment completed successfully!

To access the application locally, run:
kubectl port-forward -n otel-demo service/frontend 8080:8080
Then visit: http://localhost:8080
```

## 🔄 Making Changes

To deploy code changes:

1. **Modify your source code**
2. **Rebuild specific services:**
   ```powershell
   .\build-and-deploy.ps1 -Services @("frontend") -ImageTag "v1.0.1"
   ```
3. **Or rebuild everything:**
   ```powershell
   .\build-and-deploy.ps1 -ImageTag "v1.0.1"
   ```

The deployment will update only the changed services automatically!