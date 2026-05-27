# CI/CD Pipeline with Azure DevOps, GitOps, and AKS

A fully automated, security-gated CI/CD pipeline using **Azure DevOps**, **GitOps (ArgoCD)**, and **Azure Kubernetes Service (AKS)**. Changes pushed to this repository automatically trigger security scans, Docker builds, container vulnerability scans, and deployments to the AKS cluster via ArgoCD — all without ever pushing directly to Kubernetes.

## Architecture Overview

```
Developer
    │  git push
    ▼
GitHub (source of truth)
    │  webhook trigger
    ▼
Azure DevOps CI Pipeline
    ├── Gate 1: Gitleaks  (secret scan)
    ├── Gate 2: Checkov   (IaC misconfiguration scan)
    ├── Gate 3: Semgrep   (SAST)
    ├── Build Docker images  (linux/arm64, parallel)
    ├── Gate 4: Trivy     (container CVE scan)
    └── Push to ACR       (immutable build-ID tag)
         │
         ▼
Azure DevOps CD Pipeline
    ├── Fetch secrets from Azure Key Vault
    ├── Update k8s deployment manifests (new image tag)
    ├── Commit + push manifest change to GitHub  [skip ci]
    ├── Trigger ArgoCD sync + wait for healthy
    └── Gate 5: OWASP ZAP DAST scan
         │
         ▼ (GitOps pull)
ArgoCD (watches GitHub, self-heals)
    │  apply manifests
    ▼
AKS Cluster (3 nodes, ARM64)
    ├── python-app   (Flask,          Port 5000)
    ├── nodejs-app   (Express,        Port 3000)
    └── dotnet-app   (ASP.NET Core,   Port 8080)
         │
         ▼
NGINX Ingress Controller  (public IP: 4.158.73.97)
    ├── /python/  → python-app-svc
    ├── /nodejs/  → nodejs-app-svc
    └── /dotnet/  → dotnet-app-svc
```

## Technologies Used

| Technology | Role |
|-----------|------|
| Azure DevOps Pipelines | CI/CD orchestration |
| GitHub | Source of truth for code and manifests |
| Azure Container Registry (ACR) | Private Docker image storage |
| Azure Kubernetes Service (AKS) | Managed Kubernetes cluster |
| ArgoCD | GitOps continuous delivery engine |
| Azure Key Vault | Secrets management |
| Prometheus + Grafana | Cluster and application monitoring |
| Gitleaks | Secret scanning |
| Checkov | IaC misconfiguration scanning |
| Semgrep | SAST (static application security testing) |
| Trivy | Container CVE scanning |
| OWASP ZAP | DAST (dynamic application security testing) |
| NGINX Ingress | Path-based routing to all three services |

## Repository Structure

```
.
├── azure-pipelines/
│   ├── ci-pipeline.yml        # CI: secret scan → IaC scan → SAST → build → CVE scan → push
│   └── cd-pipeline.yml        # CD: fetch secrets → update manifests → ArgoCD sync → DAST
├── microservices/
│   ├── python-app/            # Flask REST API  (Port 5000)
│   ├── nodejs-app/            # Express REST API (Port 3000)
│   └── dotnet-app/            # ASP.NET Core REST API (Port 8080)
├── k8s/
│   ├── bootstrap/             # Applied once manually (not watched by ArgoCD)
│   │   ├── appproject.yaml    # ArgoCD AppProject (namespace scope + resource whitelist)
│   │   └── monitoring-namespace.yaml
│   ├── namespaces/            # Kubernetes namespace
│   ├── deployments/           # Deployment manifests (image tags updated by CD pipeline)
│   ├── services/              # ClusterIP services
│   ├── ingress/               # NGINX Ingress rules
│   ├── rbac/                  # ServiceAccounts (one per app)
│   ├── network-policies/      # Default-deny + per-service allow rules
│   ├── pdb/                   # PodDisruptionBudgets
│   ├── hpa/                   # HorizontalPodAutoscalers
│   ├── quotas/                # ResourceQuota + LimitRange
│   └── monitoring/            # Helm values for kube-prometheus-stack
├── argocd/
│   ├── application.yaml       # ArgoCD Application definition
│   └── project.yaml           # ArgoCD AppProject definition
├── docs/
│   ├── Project-Documentation.docx  # Full project documentation
│   ├── Project-Documentation.pdf
│   ├── setup-guide.md         # Step-by-step setup guide (start here)
│   ├── threat-model.md        # STRIDE threat analysis
│   ├── cost-estimate.md       # Azure cost breakdown
│   ├── disaster-recovery.md   # DR runbook
│   └── trade-off-matrix.md    # Architecture decision records
├── monitoring/
│   ├── README.md              # Monitoring setup notes
│   ├── log-queries.md         # Useful KQL and PromQL queries
│   └── setup-alerts.sh        # Alert configuration script
└── scripts/
    └── non-prod-shutdown.sh   # Stop/start AKS to save cost
```

## Quick Start

See **[docs/setup-guide.md](docs/setup-guide.md)** for the complete step-by-step guide with explanations and expected outputs.

### Prerequisites

| Tool | Install |
|------|---------|
| Azure CLI | `brew install azure-cli` (macOS) or [docs.microsoft.com/cli/azure/install-azure-cli](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| kubectl | `az aks install-cli` |
| Helm | `brew install helm` |
| Docker | [docker.com/get-docker](https://docker.com/get-docker) |
| Git | Pre-installed on most systems |

### One-time infrastructure setup

```bash
az login
az group create --name rg-gitops-project --location uksouth

az acr create --resource-group rg-gitops-project --name acrgitopsproject --sku Basic --admin-enabled true

az aks create \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --node-count 3 \
  --node-vm-size Standard_D2ps_v6 \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --attach-acr acrgitopsproject

az aks get-credentials --resource-group rg-gitops-project --name aks-gitops-cluster
kubectl get nodes
```

### Verify live deployments

```bash
# All pods should be Running
kubectl get pods -n microservices

# Ingress external IP
kubectl get ingress -n microservices

# Test endpoints (replace with actual Ingress IP)
curl http://<INGRESS_IP>/python/
curl http://<INGRESS_IP>/nodejs/
curl http://<INGRESS_IP>/dotnet/
```

## Security Posture

Every container runs with:
- Non-root user (UID 1001)
- Read-only root filesystem
- All Linux capabilities dropped
- Seccomp profile: RuntimeDefault
- No auto-mounted Kubernetes service account token
- NetworkPolicy: default-deny, port-specific allow per service

The pipeline blocks deployment if any of the following are detected:
- Secrets committed to source code (Gitleaks)
- Kubernetes misconfiguration (Checkov)
- Insecure code patterns (Semgrep)
- CRITICAL or HIGH CVEs in container images (Trivy)

## Monitoring

Prometheus + Grafana are deployed via Helm (kube-prometheus-stack).

```bash
# Access Grafana
kubectl get svc -n monitoring kube-prometheus-stack-grafana
# Default credentials: admin / admin
```

## Cost Management

See [docs/cost-estimate.md](docs/cost-estimate.md). To stop the cluster when not in use:

```bash
bash scripts/non-prod-shutdown.sh stop
bash scripts/non-prod-shutdown.sh start
```
