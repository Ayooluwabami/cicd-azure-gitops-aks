# CI/CD Pipeline with Azure DevOps, GitOps, and AKS

A fully automated CI/CD pipeline using **Azure DevOps**, **GitOps (ArgoCD)**, and **Azure Kubernetes Service (AKS)**. Changes pushed to this repository automatically trigger builds, push Docker images to Azure Container Registry, and deploy updates to the AKS cluster via ArgoCD.

## Architecture Overview

```
GitHub Repo ──► Azure DevOps CI Pipeline ──► Azure Container Registry (ACR)
     │                                                  │
     │          (updates k8s manifests)                 │
     └──► Azure DevOps CD Pipeline ──────► ArgoCD ──► AKS Cluster
                                            (GitOps)   ├── python-app
                                                       ├── nodejs-app
                                                       └── dotnet-app
```

## Technologies Used
- **Azure DevOps** — Source code management & pipelines
- **Azure Repos / GitHub** — Version control
- **Azure Pipelines** — CI/CD automation
- **Azure Container Registry (ACR)** — Container image storage
- **ArgoCD** — GitOps-based continuous delivery
- **AKS (Azure Kubernetes Service)** — Deployment environment
- **Microservices** — Python (Flask), Node.js (Express), .NET (ASP.NET Core)

## Repository Structure
```
.
├── microservices/
│   ├── python-app/          # Flask REST API
│   ├── nodejs-app/          # Express REST API
│   └── dotnet-app/          # ASP.NET Core REST API
├── k8s/
│   ├── namespaces/          # Kubernetes namespace definitions
│   ├── deployments/         # Deployment manifests for each service
│   └── services/            # Service (LoadBalancer) manifests
├── argocd/
│   ├── application.yaml     # ArgoCD Application definition
│   └── project.yaml         # ArgoCD Project definition
├── azure-pipelines/
│   ├── ci-pipeline.yml      # CI: Build & push Docker images
│   └── cd-pipeline.yml      # CD: Update k8s manifests
└── docs/
    └── setup-guide.md       # Full step-by-step setup guide
```

## Quick Start

### Prerequisites
- Azure subscription
- Azure CLI installed
- `kubectl` installed
- `argocd` CLI installed
- Docker installed
- Azure DevOps account

### 1. Infrastructure Setup

#### Create AKS Cluster
```bash
# Login to Azure
az login

# Create resource group
az group create --name rg-gitops-project --location eastus

# Create AKS cluster (3 nodes)
az aks create \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --node-count 3 \
  --enable-addons monitoring \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group rg-gitops-project --name aks-gitops-cluster
```

#### Create Azure Container Registry
```bash
az acr create \
  --resource-group rg-gitops-project \
  --name acrgitopsproject \
  --sku Basic

# Attach ACR to AKS
az aks update \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --attach-acr acrgitopsproject
```

### 2. Install ArgoCD
```bash
# Create namespace
kubectl create namespace argocd

# Apply ArgoCD manifests
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose ArgoCD UI
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Login via CLI
argocd login <ARGOCD_EXTERNAL_IP> --username admin --password <PASSWORD>
```

### 3. Connect AKS to ArgoCD
```bash
# Add cluster
argocd cluster add <CONTEXT_NAME>

# Deploy ArgoCD Application
kubectl apply -f argocd/application.yaml
```

### 4. Apply Kubernetes Manifests
```bash
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/deployments/
kubectl apply -f k8s/services/
```

### 5. Verify Deployment
```bash
# Check pods
kubectl get pods -n microservices

# Get external IPs
kubectl get svc -n microservices
```

See [docs/setup-guide.md](docs/setup-guide.md) for the full step-by-step guide with screenshots.
