# Complete Setup Guide

## CI/CD Pipeline with Azure DevOps, GitOps (ArgoCD), and AKS

**Institution:** Cloudboosta Academy — AWS Cloud DevOps Training  
**Group:** 2

---

## What You Will Build

By following this guide you will have:

- A 3-node Azure Kubernetes cluster running three microservices (Python, Node.js, .NET)
- A CI pipeline that scans code for secrets, misconfigurations, and vulnerabilities before building images
- A CD pipeline that updates Kubernetes manifests and deploys via GitOps (ArgoCD)
- All secrets stored in Azure Key Vault — never in code or pipeline variables
- Prometheus and Grafana for cluster monitoring
- A self-hosted ARM64 pipeline agent

**No prior cloud or DevOps experience is assumed.** Every step is explained.

---

## Glossary (Read This First)

| Term | What It Means |
|------|--------------|
| **Azure** | Microsoft's cloud platform — you rent servers and services instead of owning hardware |
| **AKS** | Azure Kubernetes Service — a managed cluster of virtual machines that runs containers |
| **Kubernetes** | Software that manages containers at scale — starts them, restarts crashed ones, balances traffic |
| **Container** | A packaged application that runs the same way on any machine |
| **Docker** | The tool that creates containers |
| **ACR** | Azure Container Registry — private storage for your container images (like Docker Hub but private) |
| **CI Pipeline** | A chain of automated steps that run every time you push code |
| **CD Pipeline** | A chain of automated steps that deploy the new version after CI passes |
| **GitOps** | A deployment model where Git is the source of truth — the cluster always matches what Git says |
| **ArgoCD** | The GitOps tool that watches your GitHub repo and applies changes to the cluster |
| **Key Vault** | Azure's secure secret store — passwords and tokens stored here are never visible in logs |
| **SAST** | Static Application Security Testing — scanning source code for vulnerabilities without running it |
| **DAST** | Dynamic Application Security Testing — sending HTTP requests to a running app to find vulnerabilities |
| **Trivy** | A tool that scans container images for known CVEs (security vulnerabilities) |
| **Checkov** | A tool that scans Kubernetes YAML files for security misconfigurations |
| **Gitleaks** | A tool that scans git commits for accidentally committed passwords or API keys |
| **Semgrep** | A static code analysis tool that finds insecure code patterns |
| **Helm** | A package manager for Kubernetes — like apt/brew but for K8s apps |
| **Ingress** | A Kubernetes resource that routes external HTTP traffic to services inside the cluster |

---

## Prerequisites

### 1. Accounts Required

| Account | URL | Notes |
|---------|-----|-------|
| Azure | https://portal.azure.com | Free trial gives $200 credit |
| Azure DevOps | https://dev.azure.com | Free for up to 5 users |
| GitHub | https://github.com | Free |

### 2. Tools to Install on Your Local Machine

**Azure CLI** — used to create and manage Azure resources from the terminal.

```bash
# macOS
brew install azure-cli

# Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify installation
az --version
# Expected: azure-cli 2.x.x
```

**kubectl** — the command-line tool for Kubernetes.

```bash
# After Azure CLI is installed:
az aks install-cli

# Verify
kubectl version --client
# Expected: Client Version: v1.x.x
```

**Helm** — Kubernetes package manager, used to install Prometheus + Grafana.

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}
```

**Docker** — to build container images locally (optional for setup, required on the agent VM).

Download from: https://www.docker.com/get-docker

**Git** — version control.

```bash
# macOS (usually pre-installed)
git --version

# Ubuntu
sudo apt-get install git
```

---

## Phase 1 — Azure Account Setup

### Step 1.1 — Login to Azure

Open a terminal and run:

```bash
az login
```

A browser window opens. Sign in with your Azure account. When done, your terminal shows:

```
[
  {
    "cloudName": "AzureCloud",
    "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "isDefault": true,
    "name": "Your Subscription Name",
    "state": "Enabled",
    "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    ...
  }
]
```

Note your subscription ID (the `id` field). If you have multiple subscriptions, set the correct one:

```bash
az account set --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Step 1.2 — Create a Resource Group

A resource group is a logical container for all Azure resources in this project. Think of it as a project folder in the cloud.

```bash
az group create \
  --name rg-gitops-project \
  --location uksouth
```

Expected output:
```json
{
  "id": "/subscriptions/.../resourceGroups/rg-gitops-project",
  "location": "uksouth",
  "name": "rg-gitops-project",
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

> **Why uksouth?** Any Azure region works. Use a region where your VM quota allows the Standard_D2ps_v6 SKU (ARM64). You can check availability with: `az vm list-skus --location uksouth --size Standard_D2ps_v6 --output table`

---

## Phase 2 — Azure Container Registry (ACR)

ACR is a private Docker image registry. Container images built by the pipeline are stored here. The AKS cluster pulls images from ACR.

### Step 2.1 — Create ACR

```bash
az acr create \
  --resource-group rg-gitops-project \
  --name acrgitopsproject \
  --sku Basic \
  --admin-enabled true
```

Expected output (condensed):
```json
{
  "adminUserEnabled": true,
  "loginServer": "acrgitopsproject.azurecr.io",
  "name": "acrgitopsproject",
  "provisioningState": "Succeeded",
  "sku": { "name": "Basic" }
}
```

> **ACR name must be globally unique.** If `acrgitopsproject` is taken, choose another name and update all references in the pipeline YAML files.

---

## Phase 3 — AKS Cluster

AKS is a managed Kubernetes service. Azure handles the control plane (the management layer); you manage the worker nodes (the machines that run your containers).

### Step 3.1 — Create the AKS Cluster

```bash
az aks create \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --node-count 3 \
  --node-vm-size Standard_D2ps_v6 \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --attach-acr acrgitopsproject
```

This command takes 5–10 minutes. What each flag does:

| Flag | Meaning |
|------|---------|
| `--node-count 3` | Create 3 worker nodes |
| `--node-vm-size Standard_D2ps_v6` | Each node is an ARM64 VM (2 vCPU, 4GB RAM) |
| `--enable-addons monitoring` | Enable Azure Monitor for containers |
| `--generate-ssh-keys` | Create SSH keys for node access |
| `--attach-acr acrgitopsproject` | Allow the cluster to pull images from ACR without extra credentials |

Expected output (condensed):
```json
{
  "name": "aks-gitops-cluster",
  "provisioningState": "Succeeded",
  "agentPoolProfiles": [
    {
      "count": 3,
      "vmSize": "Standard_D2ps_v6",
      "osType": "Linux"
    }
  ]
}
```

> **ARM64 nodes:** Standard_D2ps_v6 is an ARM64 (Ampere) VM. All Docker images must be built for `linux/arm64`. The CI pipeline handles this automatically.

### Step 3.2 — Connect kubectl to the Cluster

Download the cluster credentials so `kubectl` commands go to your AKS cluster:

```bash
az aks get-credentials \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster
```

Expected output:
```
Merged "aks-gitops-cluster" as current context in /Users/<you>/.kube/config
```

Verify the connection:

```bash
kubectl get nodes
```

Expected output (all nodes should show `Ready`):
```
NAME                                STATUS   ROLES   AGE   VERSION
aks-nodepool1-xxxxxxxx-vmss000000   Ready    agent   3m    v1.29.x
aks-nodepool1-xxxxxxxx-vmss000001   Ready    agent   3m    v1.29.x
aks-nodepool1-xxxxxxxx-vmss000002   Ready    agent   3m    v1.29.x
```

> If a node shows `NotReady`, wait 2 more minutes and retry.

---

## Phase 4 — Azure Key Vault

Key Vault stores secrets (passwords, API tokens) securely. The pipeline fetches secrets from Key Vault at runtime — they never appear in code, YAML files, or pipeline logs.

### Step 4.1 — Create the Key Vault

```bash
az keyvault create \
  --name kv-gitops-project \
  --resource-group rg-gitops-project \
  --location uksouth
```

Expected output (condensed):
```json
{
  "name": "kv-gitops-project",
  "properties": {
    "vaultUri": "https://kv-gitops-project.vault.azure.net/",
    "provisioningState": "Succeeded"
  }
}
```

> **Key Vault name must be globally unique.** If the name is taken, choose another and update `KEY_VAULT_NAME` in `cd-pipeline.yml`.

---

## Phase 5 — ArgoCD Installation

ArgoCD is the GitOps engine. It watches your GitHub repository for changes to the `k8s/` directory. When it detects a change (e.g., a new image tag), it automatically applies that change to the cluster. If someone manually changes a resource in the cluster, ArgoCD reverts it — the cluster always matches what GitHub says.

### Step 5.1 — Create the ArgoCD Namespace

```bash
kubectl create namespace argocd
```

Expected output:
```
namespace/argocd created
```

### Step 5.2 — Install ArgoCD

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

This downloads and installs ~30 Kubernetes resources. Wait for all pods to be ready:

```bash
kubectl wait --for=condition=ready pod \
  --all -n argocd --timeout=300s
```

Expected output (after ~2 minutes):
```
pod/argocd-application-controller-0 condition met
pod/argocd-dex-server-xxxxxxxxxx-xxxxx condition met
pod/argocd-redis-xxxxxxxxxx-xxxxx condition met
pod/argocd-repo-server-xxxxxxxxxx-xxxxx condition met
pod/argocd-server-xxxxxxxxxx-xxxxx condition met
```

### Step 5.3 — Expose the ArgoCD Web UI

By default ArgoCD is not accessible from outside the cluster. Expose it via a public LoadBalancer:

```bash
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'
```

Wait for the external IP to be assigned (takes 1–3 minutes):

```bash
kubectl get svc argocd-server -n argocd --watch
```

When the `EXTERNAL-IP` column changes from `<pending>` to an IP address, press `Ctrl+C`.

```
NAME            TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)
argocd-server   LoadBalancer   10.0.x.x     20.162.177.70    80:xxxxx/TCP,443:xxxxx/TCP
```

Note this IP — it is your ArgoCD UI address.

### Step 5.4 — Get the Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

This prints a randomly generated password. Save it — you need it to log in.

### Step 5.5 — Store the Password in Key Vault

```bash
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

az keyvault secret set \
  --vault-name kv-gitops-project \
  --name argocd-admin-password \
  --value "$ARGOCD_PASSWORD"
```

Expected output:
```json
{
  "id": "https://kv-gitops-project.vault.azure.net/secrets/argocd-admin-password/...",
  "name": "argocd-admin-password"
}
```

### Step 5.6 — Install the ArgoCD CLI

```bash
# Detect architecture automatically
ARGOCD_VERSION="v3.4.2"
ARCH=$(uname -m)
if [ "${ARCH}" = "aarch64" ]; then ARGOCD_ARCH="arm64"; else ARGOCD_ARCH="amd64"; fi

curl -sSL -o /tmp/argocd \
  "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARGOCD_ARCH}"
sudo mv /tmp/argocd /usr/local/bin/argocd
sudo chmod +x /usr/local/bin/argocd

# Verify
argocd version --client
```

Expected output:
```
argocd: v3.4.2
  BuildDate: ...
```

### Step 5.7 — Login to ArgoCD via CLI

```bash
ARGOCD_IP="20.162.177.70"   # Replace with your actual IP from Step 5.3

argocd login ${ARGOCD_IP} \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --grpc-web \
  --insecure
```

Expected output:
```
'admin:login' logged in successfully
Context '20.162.177.70' updated
```

### Step 5.8 — Access the ArgoCD UI

Open `http://20.162.177.70` in your browser. Log in with:
- **Username:** admin
- **Password:** (the password from Step 5.4)

---

## Phase 6 — GitHub Repository Setup

### Step 6.1 — Fork or Clone the Repository

Fork the repository on GitHub: https://github.com/Ayooluwabami/cicd-azure-gitops-aks

Then clone it locally:

```bash
git clone https://github.com/<YOUR_USERNAME>/cicd-azure-gitops-aks.git
cd cicd-azure-gitops-aks
```

### Step 6.2 — Create a GitHub Personal Access Token (PAT)

The CD pipeline commits updated manifest files back to GitHub. It needs a token to do this.

**GUI Steps:**
1. Go to https://github.com/settings/tokens
2. Click **Generate new token (classic)**
3. Give it a name: `azure-devops-cd-pipeline`
4. Select expiry: 90 days
5. Select scopes: check **repo** (full control of private repositories)
6. Click **Generate token**
7. Copy the token immediately — GitHub shows it only once

### Step 6.3 — Store the PAT in Key Vault

```bash
az keyvault secret set \
  --vault-name kv-gitops-project \
  --name github-pat \
  --value "ghp_xxxxxxxxxxxxxxxxxxxx"   # Replace with your actual PAT
```

---

## Phase 7 — ArgoCD AppProject and Application

The ArgoCD AppProject defines what the ArgoCD Application is allowed to deploy. It acts as a security boundary — ArgoCD can only manage resources in the `microservices` namespace.

### Step 7.1 — Apply the AppProject

```bash
kubectl apply -f k8s/bootstrap/appproject.yaml
```

Expected output:
```
appproject.argoproj.io/microservices-project created
```

### Step 7.2 — Connect the GitHub Repository to ArgoCD

```bash
GITHUB_PAT="ghp_xxxxxxxxxxxxxxxxxxxx"   # Your PAT from Step 6.2

argocd repo add https://github.com/<YOUR_USERNAME>/cicd-azure-gitops-aks.git \
  --username <YOUR_GITHUB_USERNAME> \
  --password "${GITHUB_PAT}"
```

Expected output:
```
Repository 'https://github.com/<YOUR_USERNAME>/cicd-azure-gitops-aks.git' added
```

### Step 7.3 — Update the Application Manifest

Edit `argocd/application.yaml` and update the `repoURL` to point to your fork:

```yaml
spec:
  source:
    repoURL: https://github.com/<YOUR_USERNAME>/cicd-azure-gitops-aks.git
```

### Step 7.4 — Deploy the ArgoCD Application

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application.yaml
```

Expected output:
```
appproject.argoproj.io/microservices-project configured
application.argoproj.io/microservices-app created
```

ArgoCD will immediately begin syncing the `k8s/` directory to the cluster.

### Step 7.5 — Watch the First Sync

```bash
argocd app get microservices-app --grpc-web --insecure
```

After 1–2 minutes, the status should show:
```
Health Status:    Healthy
Sync Status:      Synced
```

In the ArgoCD UI, you should see the `microservices-app` application with all resources in green.

---

## Phase 8 — Install NGINX Ingress Controller

The Ingress controller handles external HTTP traffic and routes it to the correct service based on the URL path.

### Step 8.1 — Add the Helm Repository

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### Step 8.2 — Install NGINX Ingress

```bash
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

Wait for the LoadBalancer IP:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx --watch
```

Note the `EXTERNAL-IP` — this is your public-facing Ingress IP (`4.158.73.97` in the project).

---

## Phase 9 — Monitoring (Prometheus + Grafana)

Prometheus collects metrics from the cluster. Grafana provides dashboards to visualise them.

### Step 9.1 — Add the Helm Repository

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 9.2 — Create the Monitoring Namespace

```bash
kubectl apply -f k8s/bootstrap/monitoring-namespace.yaml
```

### Step 9.3 — Install kube-prometheus-stack

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/helm-values.yaml
```

Wait for all pods to be ready:

```bash
kubectl get pods -n monitoring --watch
```

All pods should reach `Running` status within 3–5 minutes.

### Step 9.4 — Get the Grafana External IP

```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring
```

Open `http://<GRAFANA_IP>` in a browser. Default credentials: `admin` / `admin`.

---

## Phase 10 — Azure DevOps Setup

### Step 10.1 — Create an Azure DevOps Organization and Project

**GUI Steps:**
1. Go to https://dev.azure.com
2. Click **New organization** (if you don't have one)
3. Name the organization: `gitops-cicd-org`
4. Create a project: name it `gitops-cicd`, visibility: **Private**

### Step 10.2 — Create a Service Connection

The service connection allows Azure DevOps pipelines to authenticate with Azure (to push Docker images to ACR and read Key Vault secrets).

**GUI Steps:**
1. In Azure DevOps, go to **Project Settings** (bottom-left gear icon)
2. Click **Service connections** → **New service connection**
3. Select **Azure Resource Manager** → **Next**
4. Select **Service principal (automatic)** → **Next**
5. Set the scope to your subscription
6. Name it exactly: `AZURE_SERVICE_CONNECTION`
7. Check **Grant access permission to all pipelines**
8. Click **Save**

### Step 10.3 — Grant the Service Principal Access to Key Vault

The service connection creates a Service Principal in Azure AD. You need to grant it permission to read Key Vault secrets.

First find the Service Principal ID:

**GUI Steps:**
1. In Azure DevOps, go to **Project Settings → Service connections**
2. Click `AZURE_SERVICE_CONNECTION` → **Manage Service Principal**
3. Note the **Application (client) ID**

Then grant Key Vault access via CLI:

```bash
SP_CLIENT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"   # From above

az keyvault set-policy \
  --name kv-gitops-project \
  --spn "${SP_CLIENT_ID}" \
  --secret-permissions get list
```

Expected output:
```json
{
  "properties": {
    "accessPolicies": [
      {
        "permissions": {
          "secrets": ["get", "list"]
        }
      }
    ]
  }
}
```

### Step 10.4 — Create the CI Pipeline

**GUI Steps:**
1. In Azure DevOps, go to **Pipelines** → **New pipeline**
2. Select **GitHub** as the source
3. Authorize Azure DevOps to access your GitHub account (follow the OAuth flow)
4. Select your repository: `cicd-azure-gitops-aks`
5. Select **Existing Azure Pipelines YAML file**
6. Branch: `main`, Path: `/azure-pipelines/ci-pipeline.yml`
7. Click **Continue** → **Save** (do not run yet)
8. Name the pipeline: `cicd-azure-gitops-aks` (this name must match the `source:` field in `cd-pipeline.yml`)

### Step 10.5 — Create the CD Pipeline

**GUI Steps:**
1. Go to **Pipelines** → **New pipeline**
2. Select **GitHub**, choose the same repository
3. Select **Existing Azure Pipelines YAML file**
4. Branch: `main`, Path: `/azure-pipelines/cd-pipeline.yml`
5. Click **Continue** → **Save**
6. Name the pipeline: `cicd-azure-gitops-aks (2)` or any name you prefer

---

## Phase 11 — Self-Hosted Pipeline Agent

The Azure DevOps pipelines run on a **self-hosted agent** — a VM you control. This gives full control over the build environment (pre-installed tools, persistent Docker cache, ARM64 native builds).

### Step 11.1 — Create the Agent VM

The AKS nodes are ARM64. To build `linux/arm64` images natively (no emulation), the agent VM must also be ARM64.

```bash
# Create the VM
az vm create \
  --resource-group rg-gitops-project \
  --name ado-pipeline-agent \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64:latest \
  --size Standard_D2ps_v6 \
  --admin-username azagent \
  --generate-ssh-keys \
  --public-ip-sku Standard

# Open port 22 for SSH
az vm open-port \
  --resource-group rg-gitops-project \
  --name ado-pipeline-agent \
  --port 22
```

Note the public IP from the output (e.g., `20.117.146.28`).

### Step 11.2 — SSH into the Agent VM

```bash
ssh azagent@20.117.146.28
```

### Step 11.3 — Install Required Tools on the Agent

Run these commands inside the SSH session:

```bash
# Update package list
sudo apt-get update

# Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# Add azagent to docker group so it can run docker without sudo
sudo usermod -aG docker azagent

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install kubectl
sudo az aks install-cli

# Install Python 3 and pip (required for Checkov and Semgrep)
sudo apt-get install -y python3-pip python3-venv

# Verify
docker --version
az --version
kubectl version --client
pip3 --version
```

Expected:
```
Docker version 24.x.x
azure-cli 2.x.x
Client Version: v1.x.x
pip 22.0.2 from /usr/lib/python3/dist-packages/pip (python 3.10)
```

### Step 11.4 — Create an Azure DevOps PAT for the Agent

The agent needs a PAT to authenticate with Azure DevOps.

**GUI Steps:**
1. In Azure DevOps, click your profile avatar (top right) → **Personal access tokens**
2. Click **New Token**
3. Name: `pipeline-agent`
4. Organization: select your org
5. Expiration: 90 days
6. Scopes: click **Show all scopes**, then select:
   - **Agent Pools:** Read & manage
   - **Build:** Read & execute
7. Click **Create** and copy the token immediately

### Step 11.5 — Download and Configure the Agent

Still inside the SSH session on the agent VM:

```bash
# Create agent directory
mkdir /home/azagent/agent && cd /home/azagent/agent

# Download the agent (get latest URL from:
# https://github.com/microsoft/azure-pipelines-agent/releases)
# Example for 3.x on ARM64:
wget https://vstsagentpackage.azureedge.net/agent/3.248.0/vsts-agent-linux-arm64-3.248.0.tar.gz
tar zxvf vsts-agent-linux-arm64-3.248.0.tar.gz

# Configure the agent
./config.sh \
  --url https://dev.azure.com/gitops-cicd-org \
  --auth pat \
  --token <YOUR_PAT_FROM_STEP_11.4> \
  --pool Default \
  --agent ado-pipeline-agent \
  --unattended \
  --acceptTeeEula
```

Expected output:
```
>> Connect:
Connecting to the server...
>> Register Agent:
Updating agent settings file...
Settings Saved.
```

### Step 11.6 — Run the Agent as a Service

```bash
sudo ./svc.sh install azagent
sudo ./svc.sh start
sudo ./svc.sh status
```

Expected output:
```
● vsts.agent.gitops-cicd-org.Default.ado-pipeline-agent.service
     Active: active (running) since ...
```

Verify in Azure DevOps **GUI**:
1. Go to **Organization Settings → Agent pools → Default**
2. Click **Agents** tab
3. You should see `ado-pipeline-agent` with status **Online**

---

## Phase 12 — Run the Pipeline End-to-End

### Step 12.1 — Trigger the CI Pipeline

Make a small change to trigger the pipeline:

```bash
# On your LOCAL machine (not the agent VM)
echo "# trigger" >> microservices/python-app/app.py

git add microservices/python-app/app.py
git commit -m "ci: trigger pipeline test"
git push origin main
```

### Step 12.2 — Monitor the CI Pipeline

**GUI Steps:**
1. In Azure DevOps, go to **Pipelines**
2. Click the CI pipeline run that just started
3. You should see these stages:
   - Gate 1 — Secret Scanning (Gitleaks) ✅
   - Gate 2 — IaC Scanning (Checkov) ✅
   - Gate 3 — SAST (Semgrep) ✅
   - Build · Scan · Push — python-app ✅
   - Build · Scan · Push — nodejs-app ✅
   - Build · Scan · Push — dotnet-app ✅

Total run time: approximately 8–12 minutes.

### Step 12.3 — Monitor the CD Pipeline

The CD pipeline triggers automatically when the CI pipeline completes. Watch it in **Pipelines**:

- Fetch Runtime Secrets from Key Vault ✅
- Update K8s Manifests ✅
- ArgoCD Sync + Health Gate ✅
- Gate 4 — DAST (OWASP ZAP) ✅

### Step 12.4 — Verify the Deployment

```bash
# All 6 pods should be Running (2 replicas × 3 services)
kubectl get pods -n microservices

# Check Ingress
kubectl get ingress -n microservices

# Test each service via Ingress (replace with your actual Ingress IP)
INGRESS_IP="4.158.73.97"

curl http://${INGRESS_IP}/python/
# Expected: {"service": "python-app", "status": "running", "version": "1.0.0"}

curl http://${INGRESS_IP}/nodejs/
# Expected: {"service": "nodejs-app", "status": "running", "version": "1.0.0"}

curl http://${INGRESS_IP}/dotnet/
# Expected: {"service": "dotnet-app", "status": "running", "version": "1.0.0"}

# Health checks
curl http://${INGRESS_IP}/python/health
# Expected: {"status": "healthy"}
```

### Step 12.5 — Verify GitOps Self-Healing

Test that ArgoCD reverts manual changes:

```bash
# Manually scale down python-app to 0
kubectl scale deployment python-app --replicas=0 -n microservices

# Wait 3 minutes, then check — ArgoCD should restore it to 2 replicas
kubectl get pods -n microservices
# Expected: python-app pods back at 2/2 Running
```

---

## Phase 13 — Verify Security Configuration

### Step 13.1 — Confirm Containers Run as Non-Root

```bash
kubectl exec -n microservices \
  $(kubectl get pod -n microservices -l app=python-app -o name | head -1) \
  -- id
# Expected: uid=1001(appuser) gid=1001(appgroup)

kubectl exec -n microservices \
  $(kubectl get pod -n microservices -l app=nodejs-app -o name | head -1) \
  -- id
# Expected: uid=1000(node) gid=1000(node)
```

### Step 13.2 — Confirm Read-Only Filesystem

```bash
kubectl exec -n microservices \
  $(kubectl get pod -n microservices -l app=python-app -o name | head -1) \
  -- touch /test-file
# Expected: touch: cannot touch '/test-file': Read-only file system
```

### Step 13.3 — Confirm No Service Account Token

```bash
kubectl exec -n microservices \
  $(kubectl get pod -n microservices -l app=python-app -o name | head -1) \
  -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ls: cannot access ...: No such file or directory
```

### Step 13.4 — Confirm Resource Quota

```bash
kubectl describe resourcequota -n microservices
```

Expected output shows hard limits and current usage.

---

## Troubleshooting

### ArgoCD shows "OutOfSync"

```bash
argocd app sync microservices-app --force --prune --grpc-web --insecure
```

### Pod stuck in `ImagePullBackOff`

```bash
kubectl describe pod <POD_NAME> -n microservices
```

If the error is `unauthorized: authentication required`, the ACR attachment may have expired:

```bash
az aks update \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --attach-acr acrgitopsproject
```

### Pipeline step `pip3: command not found`

SSH into the agent VM and install:

```bash
sudo apt-get install -y python3-pip python3-venv
```

### Pipeline step `QEMU exit 255`

If building on an ARM64 agent, QEMU is not needed. The pipeline YAML already handles this with:

```bash
if [ "$(uname -m)" != "aarch64" ]; then
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
fi
```

If you still see this error, verify your agent VM is ARM64: `uname -m` should return `aarch64`.

### `git push` rejected (non-fast-forward)

The CD pipeline does a `git fetch` + `git reset --hard origin/main` before modifying manifests. If this fails, check that the GitHub PAT stored in Key Vault has `repo` write scope.

### ArgoCD login hangs

Always use `--insecure` and `--grpc-web` flags to avoid interactive prompts on self-signed certificates:

```bash
argocd login <IP> --username admin --password <PASS> --grpc-web --insecure
```

### Node CPU fully utilised

Check for unexpected workloads:

```bash
kubectl top nodes
kubectl get pods --all-namespaces
```

Delete any demo or test workloads that are consuming resources:

```bash
kubectl delete deployment guestbook-ui -n default --ignore-not-found
```

---

## Cleanup — Delete All Resources

When the project is complete, delete everything to stop Azure charges:

```bash
az group delete \
  --name rg-gitops-project \
  --yes \
  --no-wait
```

This deletes the AKS cluster, ACR, Key Vault, agent VM, and all other resources in the resource group.

> **Warning:** This is irreversible. Back up any important data first.

---

## Quick Reference — Important URLs and IPs

| Resource | Value |
|----------|-------|
| ArgoCD UI | http://20.162.177.70 |
| Ingress IP | 4.158.73.97 |
| Grafana UI | http://85.210.216.241 |
| Python app | http://4.158.73.97/python/ |
| Node.js app | http://4.158.73.97/nodejs/ |
| .NET app | http://4.158.73.97/dotnet/ |
| ACR login server | acrgitopsproject.azurecr.io |
| Azure DevOps | https://dev.azure.com/gitops-cicd-org |
| GitHub repo | https://github.com/Ayooluwabami/cicd-azure-gitops-aks |

> These IPs are specific to this deployment. When you deploy from scratch, your IPs will be different. Update `cd-pipeline.yml` and `argocd/application.yaml` with your actual values.
