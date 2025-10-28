# Understanding Helm Deployments for OpenTelemetry Demo

## What Gets Deployed?

### Option 1: Official Helm Chart (What my script does)
```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install opentelemetry-demo open-telemetry/opentelemetry-demo
```

**This deploys:**
- ✅ Pre-built container images from Docker Hub/GHCR
- ✅ Official OpenTelemetry Demo application
- ✅ All microservices (frontend, checkout, payment, etc.)
- ✅ Supporting infrastructure (Jaeger, Grafana, etc.)

**Container images used:**
```yaml
# Examples of what gets deployed
frontend: ghcr.io/open-telemetry/demo:latest-frontend
checkout: ghcr.io/open-telemetry/demo:latest-checkout
payment: ghcr.io/open-telemetry/demo:latest-payment
# ... and many more
```

### Option 2: Deploy Your Local Code (Custom approach)

Your project IS the source code for the OpenTelemetry demo! Looking at your `docker-compose.yml`, I can see:

```yaml
services:
  accounting:
    image: ${IMAGE_NAME}:${DEMO_VERSION}-accounting
    build:
      context: ./
      dockerfile: ${ACCOUNTING_DOCKERFILE}
  
  ad:
    image: ${IMAGE_NAME}:${DEMO_VERSION}-ad
    build:
      context: ./
      dockerfile: ${AD_DOCKERFILE}
```

This means you have the actual source code and Dockerfiles for all services!

To deploy YOUR local code, you would need to:

1. **Build Docker images** from your source code
2. **Push them to your ACR** (Azure Container Registry)
3. **Create/modify Helm charts** to use your images
4. **Deploy your custom chart**

## Your Project Structure

You have the complete OpenTelemetry Demo source:

```
src/
├── accounting/     # .NET service with Dockerfile
├── ad/            # Java service with Dockerfile  
├── cart/          # .NET service with Dockerfile
├── checkout/      # Go service with Dockerfile
├── currency/      # C++ service with Dockerfile
├── email/         # Ruby service with Dockerfile
├── frontend/      # Next.js service with Dockerfile
├── payment/       # JavaScript service with Dockerfile
└── ...            # Many more services
```

## Two Deployment Approaches

### 🚀 **Quick Start: Official Images (Recommended)**
```powershell
# Uses pre-built images from the OpenTelemetry team
.\deploy-k8s.ps1
```
- ✅ Fast deployment
- ✅ Tested and stable
- ✅ No build time required
- ❌ Can't modify the code

### 🛠️ **Custom Build: Your Code**
```powershell
# Build and deploy your own images
.\build-and-deploy.ps1  # (I can create this script)
```
- ✅ Use your modifications
- ✅ Full control over the code
- ✅ Custom features/fixes
- ❌ Longer build time
- ❌ More complex setup

## Which Should You Use?

**For learning/testing:** Use Option 1 (Official Helm Chart)
**For development:** Use Option 2 (Build your own images)

The script I created uses Option 1 because it's faster and more reliable for getting started. But since you have the source code, you can absolutely build and deploy your own version!

Would you like me to create a script that builds your local code and deploys it to AKS?