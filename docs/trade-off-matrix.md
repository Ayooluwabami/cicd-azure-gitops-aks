# Architectural Trade-off Matrices

**Project:** CI/CD Pipeline with Azure DevOps, GitOps, and AKS
**Date:** 2026-05-25

> Every significant architectural decision in this project was evaluated against
> at least three alternatives before a choice was made. This document is the
> evidence that choices were deliberate, not accidental.
>
> A non-technical stakeholder must be able to read the **Decision** line of each
> matrix and understand why the chosen option was selected.

---

## Decision 1 — Container Orchestration Platform

**Business problem:** We need a platform to run three independently deployable microservices
(Python, Node.js, .NET), support GitOps-based delivery via ArgoCD, and demonstrate
production-grade deployment automation as required by the project brief.

**Non-functional requirements driving this decision:**
- Must support ArgoCD or equivalent GitOps tooling
- Must support Kubernetes-native manifests (the project brief specifies K8s)
- Must scale beyond 3 services without architectural redesign
- Must be available on Azure (team's chosen cloud)

| Dimension | Weight | AKS — Azure Kubernetes Service ✅ | Azure Container Apps | Azure App Service (Containers) |
|-----------|--------|----------------------------------|---------------------|-------------------------------|
| **Monthly cost (3 services, 2 replicas each)** | High | ~$90–130 (3× B2s nodes) | ~$25–60 (consumption-based) | ~$45–90 (3× B2 plans) |
| **Implementation time** | Medium | High — K8s expertise required | Low — managed abstractions | Low — familiar web app model |
| **Operational complexity** | High | High — namespace, RBAC, NetworkPolicy, resource quotas | Low — Azure manages scaling, ingress, networking | Low — Azure manages most infra |
| **Scalability ceiling** | Medium | Unlimited — enterprise-grade horizontal + vertical | Good — up to 30 replicas per container | Limited — per App Service Plan |
| **GitOps / ArgoCD support** | Required | Native — ArgoCD deploys K8s manifests directly | Not supported — no K8s manifest layer | Not supported |
| **Attack surface introduced** | Required | Moderate — K8s API server, service accounts, etcd; all mitigated via RBAC + NetworkPolicy | Low — no cluster to manage, but less visibility into runtime security | Low — but no network isolation between services |
| **Project brief alignment** | Required | Exact match — brief specifies AKS | Partial — not mentioned in brief | Partial — not mentioned in brief |
| **Team existing expertise** | High | Low — learning opportunity; aligns with project goal | Medium | High — familiar web hosting model |
| **Compliance fit** | Required | Full control over network, RBAC, pod security | Limited control — Azure abstracts enforcement | Limited control |
| **10x traffic change** | Medium | Add node pool or enable cluster autoscaler — no redesign | Auto-scales by design | Requires plan upgrade or redesign |
| **If compromised: blast radius** | Required | One compromised pod cannot reach others (NetworkPolicy + RBAC) | Services share platform; isolation depends on Azure internals | Shared App Service Plan means shared process space |

**Decision: AKS chosen.**
The project brief explicitly requires AKS. Beyond compliance with the brief, AKS is the only option that supports ArgoCD natively and gives the team full control over network isolation and pod-level security hardening. The higher cost and complexity are the trade — and are justified by the learning outcome and production fidelity.

If cost were the primary constraint and GitOps was not required, Azure Container Apps would be reconsidered.

---

## Decision 2 — GitOps Delivery Tool

**Business problem:** Once a Docker image is pushed to ACR, something must detect the change
and update the running workload in AKS. We need a delivery mechanism that is auditable,
version-controlled, and does not require direct kubectl access from the CI pipeline.

**Non-functional requirements driving this decision:**
- Deployment state must be stored in Git (source of truth)
- Changes to the cluster must be traceable to a specific commit
- Self-healing: if someone manually changes a resource, it should be reverted automatically
- Must work without granting the CI pipeline direct write access to the K8s API server

| Dimension | Weight | ArgoCD ✅ | Flux CD | Plain kubectl in CD pipeline |
|-----------|--------|-----------|---------|------------------------------|
| **Monthly cost** | High | $0 (open source, runs in cluster) | $0 (open source, runs in cluster) | $0 (no additional component) |
| **Implementation time** | Medium | Medium — UI + CLI, well-documented | Medium — CLI-only, less beginner-friendly | Low — 3 lines of `kubectl apply` in pipeline |
| **Operational complexity** | High | Medium — dedicated ArgoCD namespace, separate admin credential | Medium — Flux runs as K8s controllers, no separate UI | Low — no extra component to maintain |
| **GitOps pull model** | Required | Yes — ArgoCD polls Git; cluster pulls changes | Yes — Flux polls Git; cluster pulls changes | No — pipeline pushes directly to cluster (CI/CD push model, not GitOps) |
| **Self-healing** | Required | Yes — `selfHeal: true` reverts manual cluster changes | Yes — built-in drift reconciliation | No — drift is not detected or corrected |
| **Audit trail** | Required | Full sync history in ArgoCD UI + logs | Full sync history in K8s events | Pipeline logs only — no cluster-side audit |
| **Attack surface introduced** | Required | ArgoCD admin UI on public IP (mitigated: password in Key Vault, AppProject scope) | No UI; lower surface area | Pipeline needs direct K8s API access — larger credential blast radius |
| **Rollback** | Required | One click or one CLI command per app | CLI command; no UI | Re-run previous pipeline build |
| **Multi-cluster support** | Medium | Yes — ArgoCD manages multiple clusters from one control plane | Yes | No — one pipeline per cluster |
| **Team existing expertise** | High | Low — new tool, but extensive documentation and the project guide uses it | Very Low — steeper learning curve | High — teams already know kubectl |
| **Beginner visibility** | Medium | High — web UI shows sync status, health, pod state in real time | Low — CLI and K8s events only | Low — only pipeline logs |

**Decision: ArgoCD chosen.**
ArgoCD implements a true GitOps pull model with self-healing, an accessible UI for demonstrating sync and deployment status, and is explicitly shown in the project reference video. It introduces a small additional attack surface (admin UI) which is mitigated by Key Vault-managed credentials and AppProject namespace scoping.

Flux would be a valid alternative in a team with stronger K8s expertise and a preference for minimal attack surface. Plain kubectl is rejected because it violates the GitOps requirement (push model, no drift detection, no self-healing).

---

## Decision 3 — CI/CD Pipeline Platform

**Business problem:** We need a platform to automatically build Docker images, run security
scans, and trigger deployment when code is pushed to the main branch.

**Non-functional requirements driving this decision:**
- Must integrate with Azure services (ACR, Key Vault, AKS) without additional connectors
- Must support YAML-defined pipelines stored in the same repository
- Must provide an audit log: who triggered what, on which commit, with what outcome
- Must support parallel stages (3 microservices build simultaneously)

| Dimension | Weight | Azure DevOps ✅ | GitHub Actions | Jenkins |
|-----------|--------|----------------|----------------|---------|
| **Monthly cost** | High | $0 (free tier: 5 users, 1800 min/month) | $0 (free tier: 2000 min/month for public repos) | $0 (self-hosted) but requires a VM (~$30/month) |
| **Implementation time** | Medium | Low — native Azure integration; tasks for ACR, Key Vault, AKS built-in | Low — large marketplace of actions | High — plugins, configuration, maintenance |
| **Azure integration** | Required | Native — Service Connections to Azure with one click | Good — uses Azure Login action | Manual — credentials managed outside pipeline |
| **Pipeline as code** | Required | Yes — YAML in repo | Yes — YAML in repo | Jenkinsfile in repo (or UI-configured, which is anti-pattern) |
| **Secret management** | Required | Azure Key Vault task built in | Requires azure/get-keyvault-secrets action | HashiCorp Vault plugin or environment variables |
| **Audit log** | Required | Full pipeline run history with who triggered, branch, commit, outcome; 12-month retention | Full run history in GitHub UI | Full history but on self-hosted server — team must manage retention |
| **Attack surface introduced** | Required | Azure service connection scoped to minimum roles; secrets in Key Vault | GitHub Actions tokens scoped per workflow; OIDC for Azure auth | Jenkins master is a long-lived server — hardening required; plugin supply chain risk |
| **Parallel stages** | Medium | Yes — `dependsOn: []` for parallel stages | Yes — matrix / parallel jobs | Yes — parallel stages in Jenkinsfile |
| **Team existing expertise** | High | Low — new tool | Medium — GitHub is familiar | Low — Jenkins has a steep learning curve |
| **Project brief alignment** | Required | Exact match — brief specifies Azure DevOps | Not specified | Not specified |
| **10x pipeline volume** | Medium | Increase Microsoft-hosted agent minutes or add self-hosted agents | Add self-hosted runners | Add Jenkins agents |

**Decision: Azure DevOps chosen.**
The project brief explicitly requires Azure DevOps. It is also the strongest choice for Azure-native workloads — built-in service connections, Key Vault tasks, and ACR integration reduce the pipeline configuration to a minimum. The free tier is sufficient for the project's build volume.

GitHub Actions would be the natural alternative if the project brief permitted it — the team already uses GitHub for the repository, and OIDC-based Azure authentication would eliminate the Service Principal entirely. This is noted as the preferred evolution path for a real production system.

---

## Decision 4 — Secret Management

**Business problem:** The CD pipeline needs the ArgoCD admin password and a GitHub PAT
at runtime. These cannot be stored in pipeline YAML or Azure DevOps variables (visible to
project admins). They need to be stored, accessed, and rotated independently of the pipeline.

| Dimension | Weight | Azure Key Vault ✅ | Azure DevOps Secret Variables | Hardcoded in YAML |
|-----------|--------|-------------------|------------------------------|-------------------|
| **Monthly cost** | High | < $1/month | $0 | $0 |
| **Visibility to admins** | Required | Not visible — access controlled by Azure RBAC separately from DevOps project | Visible to all Azure DevOps project administrators | Visible to anyone with repository read access |
| **Access logging** | Required | Every read is logged in Azure Monitor; anomalous access alerts possible | No access logging | No access logging |
| **Rotation without pipeline change** | Required | Yes — update secret in Key Vault; pipeline picks up new value on next run automatically | No — requires updating pipeline variable definition | No — requires code change and new commit |
| **Scope control** | Required | Specific secrets granted to specific Service Principals via Azure RBAC | All pipeline secrets accessible to all pipelines in the project | No scope — anyone with repo access has the secret |
| **Compliance evidence** | Required | Azure Monitor logs provide evidence of access controls | No audit trail | No audit trail |
| **Attack surface introduced** | Required | Key Vault access requires Azure RBAC role (Key Vault Secrets User) scoped to this vault only | Secret visible in UI to any DevOps admin — one compromised admin account = all secrets | Secret in git history permanently even after deletion |

**Decision: Azure Key Vault chosen.**
Hardcoded YAML is rejected outright — a secret committed to a public repository is immediately compromised and remains in git history permanently. Azure DevOps secret variables are an improvement but are visible to project administrators and have no access log. Key Vault provides the minimum acceptable secret management: access-controlled, rotation-independent, and auditable. The < $1/month cost is not a meaningful factor.
