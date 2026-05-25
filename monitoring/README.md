# Observability Setup

**Stack:** Azure Monitor + Container Insights + Log Analytics
**Coverage:** AKS cluster health, pod-level metrics, application error rates, ArgoCD sync status

---

## What We Monitor and Why

| Signal | What It Detects | Why It Matters |
|--------|----------------|----------------|
| Pod restart count | CrashLoopBackOff — app is failing to start | Silent failure: pods restart but old version keeps serving until the node recycles |
| Node CPU > 80% | Cluster under pressure | Warning before node runs out of CPU and pods are throttled |
| Node memory > 85% | Memory pressure before OOMKill | OOMKill terminates pods with no graceful shutdown |
| Container CPU > 90% of limit | App hitting its resource ceiling | Performance degradation; may indicate memory leak or traffic spike |
| Container memory > 90% of limit | Approaching OOMKill threshold | Early warning before the pod is killed |
| ArgoCD out-of-sync > 10 min | Deployment pipeline silently broken | Pipeline may have pushed to Git but ArgoCD failed to apply; cluster running stale version |
| HTTP 5xx errors | Application errors visible to users | Business impact: users receiving errors |

---

## Setup Instructions

### 1. Enable Container Insights (if not already enabled)

Container Insights was enabled at cluster creation with `--enable-addons monitoring`.
Verify it is active:

```bash
az aks addon show \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --addon monitoring
```

If `"enabled": false`, enable it:

```bash
az aks enable-addons \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --addons monitoring \
  --workspace-resource-id "<LOG_ANALYTICS_WORKSPACE_ID>"
```

### 2. Get the Log Analytics Workspace ID

```bash
az aks show \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --query addonProfiles.omsagent.config.logAnalyticsWorkspaceResourceID \
  -o tsv
```

### 3. Create All Alert Rules

Run the setup script — it creates all alert rules defined in this directory:

```bash
bash monitoring/setup-alerts.sh
```

The script requires:
- Azure CLI logged in (`az login`)
- An email address to receive alert notifications (prompted on first run)

### 4. Access the Dashboards

| Dashboard | URL |
|-----------|-----|
| AKS Insights (pods, nodes, containers) | Azure Portal → AKS cluster → Insights |
| Log Analytics (query raw logs) | Azure Portal → Log Analytics Workspace → Logs |
| Alert history | Azure Portal → Monitor → Alerts |

---

## Files in This Directory

| File | Purpose |
|------|---------|
| `setup-alerts.sh` | Creates all Azure Monitor alert rules via Azure CLI |
| `log-queries.md` | KQL queries for common troubleshooting scenarios |
| `README.md` | This file |
