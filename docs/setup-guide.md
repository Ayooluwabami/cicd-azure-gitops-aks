# Step-by-Step Setup Guide

## CI/CD Pipeline with Azure DevOps, GitOps, and AKS

---

## Prerequisites

Install the following tools before starting:

| Tool | Purpose | Install |
|------|---------|---------|
| Azure CLI | Manage Azure resources | `brew install azure-cli` |
| kubectl | Interact with Kubernetes | `az aks install-cli` |
| ArgoCD CLI | Manage ArgoCD | See Step 2 |
| Docker | Build container images | [docker.com](https://docker.com) |
| Git | Version control | Pre-installed on most systems |

---

## Phase 1 — Infrastructure Setup

### Step 1.1 — Login to Azure

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

### Step 1.2 — Create a Resource Group

```bash
az group create \
  --name rg-gitops-project \
  --location eastus
```

### Step 1.3 — Create Azure Container Registry (ACR)

```bash
az acr create \
  --resource-group rg-gitops-project \
  --name acrgitopsproject \
  --sku Basic \
  --admin-enabled true
```

Retrieve credentials:

```bash
az acr credential show --name acrgitopsproject
```

### Step 1.4 — Create AKS Cluster (3 Nodes)

```bash
az aks create \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --node-count 3 \
  --node-vm-size Standard_B2s \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --attach-acr acrgitopsproject
```

> This creates a 3-node AKS cluster and attaches ACR so pods can pull images without extra credentials.

### Step 1.5 — Connect kubectl to AKS

```bash
az aks get-credentials \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster

# Verify connection
kubectl get nodes
```

Expected output:
```
NAME                                STATUS   ROLES   AGE
aks-nodepool1-XXXXXXXX-vmss000000   Ready    agent   2m
aks-nodepool1-XXXXXXXX-vmss000001   Ready    agent   2m
aks-nodepool1-XXXXXXXX-vmss000002   Ready    agent   2m
```

---

## Phase 2 — Install and Configure ArgoCD

### Step 2.1 — Create ArgoCD Namespace

```bash
kubectl create namespace argocd
```

### Step 2.2 — Deploy ArgoCD

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for all pods to be ready:

```bash
kubectl wait --for=condition=ready pod \
  --all -n argocd --timeout=300s
```

### Step 2.3 — Expose the ArgoCD UI

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Wait for external IP (takes ~2 minutes)
kubectl get svc argocd-server -n argocd --watch
```

### Step 2.4 — Retrieve Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

Save this password — you will need it for the UI and CLI.

### Step 2.5 — Install ArgoCD CLI

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```

### Step 2.6 — Login to ArgoCD

```bash
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

argocd login $ARGOCD_IP \
  --username admin \
  --password <PASSWORD_FROM_STEP_2.4> \
  --insecure
```

---

## Phase 3 — Connect AKS Cluster to ArgoCD

### Step 3.1 — Get the Cluster Context Name

```bash
kubectl config get-contexts
```

Note the context name for your AKS cluster (e.g., `aks-gitops-cluster`).

### Step 3.2 — Add AKS Cluster to ArgoCD

```bash
argocd cluster add aks-gitops-cluster
```

### Step 3.3 — Verify in ArgoCD Dashboard

Open `http://<ARGOCD_IP>` in your browser, log in, and confirm the cluster appears under **Settings → Clusters**.

---

## Phase 4 — Connect GitHub Repository to ArgoCD

### Step 4.1 — Add the Repository

```bash
argocd repo add https://github.com/<YOUR_USERNAME>/cicd-azure-gitops-aks.git \
  --username <GITHUB_USERNAME> \
  --password <GITHUB_PAT>
```

> Generate a GitHub Personal Access Token (PAT) with `repo` scope at: GitHub → Settings → Developer Settings → Personal Access Tokens.

### Step 4.2 — Deploy the ArgoCD Application

Update `argocd/application.yaml` to replace `<YOUR_GITHUB_USERNAME>` with your actual GitHub username, then apply:

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application.yaml
```

---

## Phase 5 — Application Deployment with ArgoCD

### Step 5.1 — Apply Kubernetes Manifests

```bash
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/deployments/
kubectl apply -f k8s/services/
```

### Step 5.2 — Monitor Sync in ArgoCD UI

Open the ArgoCD UI — the `microservices-app` application should appear and begin syncing automatically.

### Step 5.3 — Verify Running Pods

```bash
kubectl get pods -n microservices
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
python-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
python-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
nodejs-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
nodejs-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
dotnet-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
dotnet-app-XXXXXXXXX-XXXXX    1/1     Running   0          1m
```

### Step 5.4 — Retrieve External IPs

```bash
kubectl get svc -n microservices
```

Access each service in a browser:
- `http://<PYTHON_APP_IP>/`
- `http://<NODEJS_APP_IP>/`
- `http://<DOTNET_APP_IP>/`

---

## Phase 6 — CI/CD Pipeline Implementation

### Step 6.1 — Create Azure DevOps Project

1. Go to [dev.azure.com](https://dev.azure.com)
2. Create a new organization and project named `gitops-cicd`
3. Navigate to **Pipelines → New Pipeline**

### Step 6.2 — Set Up Service Connection

1. Go to **Project Settings → Service Connections**
2. Click **New Service Connection → Azure Resource Manager**
3. Select **Service Principal (automatic)**
4. Name it `AZURE_SERVICE_CONNECTION`

### Step 6.3 — Create CI Pipeline

1. Go to **Pipelines → New Pipeline**
2. Connect to your GitHub repository
3. Select **Existing Azure Pipelines YAML file**
4. Choose `/azure-pipelines/ci-pipeline.yml`
5. Save and run

### Step 6.4 — Set Pipeline Variables

In the CI pipeline, add these variables under **Variables**:

| Variable | Value |
|----------|-------|
| `AZURE_SERVICE_CONNECTION` | `AZURE_SERVICE_CONNECTION` |
| `ACR_NAME` | `acrgitopsproject` |

### Step 6.5 — Create CD Pipeline

1. Create another pipeline using `/azure-pipelines/cd-pipeline.yml`
2. Add these secret variables:

| Variable | Value | Secret |
|----------|-------|--------|
| `ARGOCD_SERVER` | `<ARGOCD_EXTERNAL_IP>` | No |
| `ARGOCD_PASSWORD` | `<ARGOCD_ADMIN_PASSWORD>` | Yes |

### Step 6.6 — Set Up Self-Hosted Agent (Optional)

If using a self-hosted agent:

```bash
# On your agent VM, install dependencies
sudo apt-get update
sudo apt-get install -y docker.io kubectl

# Download and configure the Azure Pipelines agent
mkdir myagent && cd myagent
curl -O https://vstsagentpackage.azureedge.net/agent/3.x.x/vsts-agent-linux-x64-3.x.x.tar.gz
tar zxvf vsts-agent-linux-x64-3.x.x.tar.gz
./config.sh  # Follow prompts to connect to Azure DevOps
./run.sh
```

---

## Phase 7 — Testing and Validation

### Step 7.1 — Trigger a Code Change

Make a visible change to one of the services:

```bash
# Edit the Python app version
sed -i 's/VERSION = "1.0.0"/VERSION = "2.0.0"/' microservices/python-app/app.py

git add microservices/python-app/app.py
git commit -m "feat: bump python-app version to 2.0.0"
git push origin main
```

### Step 7.2 — Verify CI Pipeline Runs

1. Go to **Azure DevOps → Pipelines**
2. Confirm the CI pipeline triggered automatically
3. Verify it built and pushed new images to ACR

Check ACR:

```bash
az acr repository show-tags \
  --name acrgitopsproject \
  --repository python-app \
  --output table
```

### Step 7.3 — Verify CD Pipeline and ArgoCD Sync

1. Confirm the CD pipeline updated the `k8s/deployments/python-app-deployment.yaml` with the new image tag
2. In the ArgoCD UI, observe the automatic sync
3. Check new pods are rolling out:

```bash
kubectl rollout status deployment/python-app -n microservices
```

### Step 7.4 — Confirm Application Update in Browser

```bash
# Get external IP
kubectl get svc python-app-svc -n microservices

# Test the endpoint
curl http://<EXTERNAL_IP>/
# Expected: {"service": "python-app", "status": "running", "version": "2.0.0"}
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Developer                               │
│                    git push → GitHub                            │
└─────────────────────┬───────────────────────────────────────────┘
                      │ webhook trigger
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure DevOps                                  │
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────────────────┐  │
│  │   CI Pipeline    │         │       CD Pipeline            │  │
│  │                  │         │                              │  │
│  │ 1. Checkout code │─────────► 1. Update k8s manifests     │  │
│  │ 2. Build Docker  │  build  │    with new image tag        │  │
│  │    images        │  done   │ 2. Push changes to GitHub    │  │
│  │ 3. Push to ACR   │         │ 3. Trigger ArgoCD sync       │  │
│  └──────────────────┘         └──────────────┬───────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                               │ git pull (GitOps)
                      ┌────────────────────────▼────────────────┐
                      │              ArgoCD                      │
                      │  Watches GitHub repo for manifest        │
                      │  changes, auto-syncs to AKS              │
                      └────────────────────────┬────────────────┘
                                               │ deploy
                      ┌────────────────────────▼────────────────┐
                      │         AKS Cluster (3 nodes)            │
                      │                                          │
                      │  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
                      │  │python-app│ │nodejs-app│ │dotnet-  │ │
                      │  │(Flask)   │ │(Express) │ │app(.NET)│ │
                      │  │Port 5000 │ │Port 3000 │ │Port 8080│ │
                      │  └────┬─────┘ └────┬─────┘ └────┬────┘ │
                      │       │             │              │      │
                      │  ┌────▼─────────────▼──────────────▼───┐ │
                      │  │         LoadBalancer Services        │ │
                      │  │      (External IPs - Port 80)        │ │
                      │  └─────────────────────────────────────┘ │
                      └─────────────────────────────────────────┘
                                               │
                      ┌────────────────────────▼────────────────┐
                      │           Azure Container                │
                      │           Registry (ACR)                 │
                      │  python-app, nodejs-app, dotnet-app      │
                      └─────────────────────────────────────────┘
```

---

## Cleanup (After Demo)

```bash
# Delete resource group (removes all Azure resources)
az group delete --name rg-gitops-project --yes --no-wait
```
