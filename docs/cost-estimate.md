# Cost Estimate — CI/CD GitOps Project on Azure

**Estimate date:** 2026-05-25
**Region:** UK South
**Assumption:** Project-level demo usage only. No production SLA, no 24/7 uptime requirement.

---

## Monthly Cost Breakdown (Always-On)

| Resource | SKU / Config | Unit Cost | Qty | Monthly Est. |
|----------|-------------|-----------|-----|-------------|
| AKS — System node pool | Standard_D2ps_v6 (2 vCPU ARM64, 4GB) | ~$0.048/hr | 3 nodes | ~$104 |
| AKS — Cluster management fee | Free tier (< 10 nodes) | $0 | 1 | $0 |
| Azure Container Registry | Basic tier | $0.167/day | 1 | ~$5 |
| Azure Key Vault | Standard (< 10k ops/month) | ~$0.03/10k ops | 1 | < $1 |
| Azure Monitor / Log Analytics | 5 GB/day ingestion | $2.30/GB | 5 GB | ~$12 |
| Public IP addresses | Standard LoadBalancer IPs | $0.005/hr ea. | 3 (Ingress + ArgoCD + Grafana) | ~$11 |
| Azure DevOps | Free tier (5 users, 1800 CI min/mo) | $0 | 1 | $0 |
| Bandwidth egress | First 100 GB free | $0 | — | $0 |
| **TOTAL (always-on)** | | | | **~$133/month** |

---

## Cost After Non-Prod Shutdown (Recommended)

Stopping the AKS cluster outside working hours (8hrs/day, Mon–Fri = 40hrs/week ≈ 24% of the month) saves the node compute cost while the cluster is stopped. ACR, Key Vault, and networking costs continue.

| Scenario | Monthly Cost |
|----------|-------------|
| Always on | ~$133 |
| Stopped nights + weekends (40hrs/week on) | ~$50 |
| Stopped when not actively working (manual on/off) | ~$20–30 |

**Recommendation for this project:** Use `scripts/non-prod-shutdown.sh` to manually stop and start the cluster. Do not leave it running while the group is not actively using it.

---

## Security Tooling Costs (Included Above)

| Tool | Cost Model | Monthly |
|------|-----------|---------|
| Trivy (container scan) | Open source, runs in pipeline | $0 |
| Checkov (IaC scan) | Open source, runs in pipeline | $0 |
| Semgrep (SAST) | Open source tier | $0 |
| Gitleaks (secret scan) | Open source, runs in pipeline | $0 |
| Azure Key Vault | < $1/month at demo scale | < $1 |

---

## Trade-off: AKS vs Alternatives

| Dimension | AKS (Chosen) | Azure Container Apps | Azure App Service |
|-----------|-------------|---------------------|-------------------|
| Monthly cost (3 services) | ~$104 compute | ~$30–60 (serverless) | ~$30–60 (B1 tier) |
| GitOps support (ArgoCD) | Native | Not supported | Not supported |
| Demonstrates K8s skills | Yes | No | No |
| Operational complexity | High | Low | Low |
| Scalability | Enterprise-grade | Good | Limited |
| Project requirement fit | Exact match | Partial | Partial |

**Decision:** AKS is chosen because the project requirement explicitly specifies AKS. The higher cost and complexity are justified by the learning outcomes and exact alignment with the assignment brief.

---

## Cost Tagging Strategy

All Azure resources should be tagged with:

```
environment   = dev
managed-by    = terraform (or manual for this project)
project       = cicd-gitops
cost-centre   = cloud-training
```

Without tags, Azure Cost Management cannot break down spend by project, making it impossible to attribute costs or set budget alerts.
