# Disaster Recovery Plan

**System:** CI/CD Pipeline with Azure DevOps, GitOps, and AKS
**Last updated:** 2026-05-25

---

## DR Metrics

| Metric | Value | Rationale |
|--------|-------|-----------|
| **RTO** (Recovery Time Objective) | 2 hours | Time to rebuild AKS cluster + reinstall ArgoCD + re-sync all apps from Git |
| **RPO** (Recovery Point Objective) | 0 minutes (zero data loss) | All services are stateless. No database. Git is the single source of truth and is hosted externally on GitHub — unaffected by an AKS failure |
| **Recovery region** | Same region (East US) | Project scope: single-region. Cross-region DR is a residual risk (documented below) |
| **Backup verification** | N/A for application state | No persistent state to back up. Infrastructure recreated from IaC (az CLI commands in setup-guide.md). Config backed up in GitHub |
| **Failover runbook last tested** | Not tested — required before demo | Follow Section 4 of this document |
| **Security controls in DR** | Same as production | DR environment is rebuilt from the same repository; the same manifests, NetworkPolicies, RBAC, and securityContexts are applied automatically by ArgoCD |

> **Critical note on security in DR:** A DR environment with weaker controls than the original
> is not a recovery environment — it is a second attack surface. This plan does not permit
> skipping security manifests to "speed up recovery." ArgoCD applies all of them on sync.

---

## What Can Fail and What Happens

| Component | Failure Mode | Impact | Recovery Path |
|-----------|-------------|--------|---------------|
| AKS node (1 of 3) | Node becomes NotReady | Kubernetes reschedules pods to remaining nodes — automatic, no intervention | Wait for auto-recovery; if node does not recover in 10 min, cordon + drain |
| AKS cluster (all nodes) | Full cluster outage | All three services unreachable | Section 3 — Full cluster recovery |
| ArgoCD pod | CrashLoopBackOff | Automatic deployments paused; running pods unaffected | Section 2 — ArgoCD recovery |
| Azure DevOps pipeline | Pipeline fails to run | No new deployments; running version continues serving traffic | Fix pipeline YAML; re-trigger manually |
| ACR unavailable | Image pull fails on new deployments | Existing running pods continue; new pods or restarts will fail ImagePullBackOff | Existing pods keep running until next restart event; wait for ACR recovery |
| GitHub unavailable | ArgoCD cannot sync | No new deployments; running pods unaffected; ArgoCD shows OutOfSync | ArgoCD continues running last-known state; wait for GitHub recovery |
| Azure Key Vault unavailable | CD pipeline cannot fetch secrets | New deployments blocked; running pods unaffected | Wait for Key Vault recovery; Key Vault SLA is 99.9% |
| Azure subscription suspended | Everything fails | Total loss | Resolve billing; full cluster recovery from Section 3 |

---

## Section 1 — Single Node Recovery

A single node failure is handled automatically by Kubernetes (pods rescheduled). No manual intervention is needed unless the node does not recover within 10 minutes.

```bash
# Check node status
kubectl get nodes

# If one node is NotReady for > 10 minutes, cordon it (stop new pods going there)
kubectl cordon <NODE_NAME>

# Drain existing pods safely off the node
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data

# Check if Azure automatically replaced the node (AKS heals node pools)
az aks nodepool show \
  --resource-group rg-gitops-project \
  --cluster-name aks-gitops-cluster \
  --nodepool-name nodepool1

# Once replaced node appears Ready, uncordon it
kubectl uncordon <NEW_NODE_NAME>
```

**Verify:** `kubectl get pods -n microservices` — all pods should show Running.

---

## Section 2 — ArgoCD Recovery (Without Cluster Rebuild)

If ArgoCD itself crashes but the cluster is healthy:

```bash
# Check ArgoCD pod status
kubectl get pods -n argocd

# If pods are in CrashLoopBackOff or Error, restart the deployment
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-application-controller -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd

# Wait for pods to be ready
kubectl wait --for=condition=ready pod \
  --all -n argocd --timeout=120s

# Verify sync resumes
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ArgoCD UI: http://$ARGOCD_IP"
```

**Verify:** Open the ArgoCD UI → microservices-app should show Synced + Healthy within 3 minutes.

---

## Section 3 — Full Cluster Recovery (AKS Total Loss)

**Estimated time: 45–90 minutes**

This is the worst-case scenario. The entire AKS cluster is gone or unrecoverable.
Because all state is in GitHub and all configuration is in code, recovery is a
rebuild — not a restore.

### Step 3.1 — Provision New AKS Cluster

```bash
# Authenticate
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create resource group (if also lost)
az group create --name rg-gitops-project --location eastus

# Create AKS cluster — same spec as original
az aks create \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster \
  --node-count 3 \
  --node-vm-size Standard_B2s \
  --enable-addons monitoring \
  --generate-ssh-keys \
  --attach-acr acrgitopsproject

# Get credentials
az aks get-credentials \
  --resource-group rg-gitops-project \
  --name aks-gitops-cluster

# Verify nodes
kubectl get nodes
```

Expected: 3 nodes in Ready state within ~5 minutes of the command completing.

### Step 3.2 — Reinstall ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=ready pod \
  --all -n argocd --timeout=300s

# Expose the UI
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Retrieve the new admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

### Step 3.3 — Update Key Vault With New ArgoCD Password

```bash
az keyvault secret set \
  --vault-name kv-gitops-project \
  --name argocd-admin-password \
  --value "<NEW_ARGOCD_PASSWORD>"
```

> Do not store the new password anywhere except Key Vault.
> Do not paste it into chat, email, or a document.

### Step 3.4 — Reconnect GitHub Repository to ArgoCD

```bash
ARGOCD_IP=$(kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

argocd login $ARGOCD_IP \
  --username admin \
  --password "<NEW_ARGOCD_PASSWORD>" \
  --grpc-web

# Fetch GitHub PAT from Key Vault
GITHUB_PAT=$(az keyvault secret show \
  --vault-name kv-gitops-project \
  --name github-pat \
  --query value -o tsv)

argocd repo add https://github.com/Ayooluwabami/cicd-azure-gitops-aks.git \
  --username Ayooluwabami \
  --password "$GITHUB_PAT"
```

### Step 3.5 — Deploy ArgoCD Project and Application

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/application.yaml
```

ArgoCD will now pull all manifests from GitHub and apply them — including the namespace,
RBAC, NetworkPolicies, ResourceQuota, and all three deployments.

### Step 3.6 — Verify Full Recovery

```bash
# All pods should be Running within 5 minutes of the ArgoCD sync
kubectl get pods -n microservices

# Get the new external IPs (they change on cluster rebuild)
kubectl get svc -n microservices

# Test each service
curl http://<PYTHON_APP_IP>/health
curl http://<NODEJS_APP_IP>/health
curl http://<DOTNET_APP_IP>/health
```

Expected response from each: `{"status": "healthy"}`

---

## Section 4 — DR Test Procedure

**This must be run before the project demo to verify the 2-hour RTO is realistic.**

1. Note the current external IPs of all three services
2. Run `scripts/non-prod-shutdown.sh stop` to stop the cluster (simulates outage)
3. Start a timer
4. Follow Section 3 completely, from scratch
5. Stop the timer when all three `/health` endpoints return `200 OK`
6. Record the actual recovery time in the table below
7. Update the **Last tested** date at the top of this document

| Test date | Tester | Actual recovery time | Notes |
|-----------|--------|---------------------|-------|
| (not yet tested) | — | — | — |

---

## Residual DR Risks (Accepted)

| Risk | Accepted Reason | Compensating Control |
|------|----------------|---------------------|
| Single-region deployment — an East US region outage takes down everything | Cross-region AKS replication costs ~2× and is out of scope for an academic project | Document impact: full outage; recovery requires choosing a new region and rebuilding |
| No automated DR trigger — recovery is always manual | Automated failover (Azure Traffic Manager + multi-region AKS) is enterprise-grade and out of scope | Monitor Azure Service Health alerts; initiate manual recovery from this runbook |
| ACR images not replicated to a second region | Geo-replication is ~$45/month extra | On full cluster rebuild in a new region: re-run CI pipeline to push images to ACR in that region |
