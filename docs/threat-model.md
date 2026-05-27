# Threat Model — CI/CD Pipeline with Azure DevOps, GitOps, and AKS

**System:** Cloud Engineering Project
**Last reviewed:** 2026-05-25
**Review trigger:** Initial architecture build — must be reviewed on any architectural change, new data flow, or security incident.
**Security owner:** 

> **Scope:** This threat model covers the CI/CD pipeline, the AKS cluster, the three microservices, ACR, ArgoCD, and the GitHub repository. It does not cover end-user devices or the Azure control plane.

---

## 1. Assets (What the Attacker Wants)

| Asset | Sensitivity | Impact if Compromised |
|-------|------------|----------------------|
| Azure Subscription credentials | Critical | Full cloud account takeover; unlimited spend |
| ArgoCD admin password | Critical | Full Kubernetes cluster control |
| GitHub PAT (used by CD pipeline) | High | Modify GitOps source of truth; inject malicious manifests |
| ACR write credentials | High | Replace container images with malicious ones |
| AKS cluster API server | Critical | Deploy arbitrary workloads; exfiltrate secrets |
| Container images in ACR | Medium | Backdoor the application; persist in cluster |
| Microservice API endpoints | Low | DoS, reconnaissance, API abuse |
| Pipeline execution logs | Medium | Reveal environment structure, internal IPs, error details |

---

## 2. Trust Boundaries

```
┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 1: Internet → Azure Load Balancer (public boundary)    │
│  Any unauthenticated actor can reach LoadBalancer IPs.           │
│  Mitigation: K8s NetworkPolicy limits which pods accept traffic. │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 2: LoadBalancer → Pod (cluster network boundary)       │
│  AKS performs SNAT; original client IP is not visible to pod.    │
│  Mitigation: NetworkPolicy allows only port-specific traffic.    │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 3: Pod → Pod (namespace isolation boundary)            │
│  All pods in microservices namespace; default-deny applied.      │
│  Mitigation: NetworkPolicy blocks all inter-pod traffic.         │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 4: Azure DevOps Pipeline → ACR / GitHub / AKS         │
│  Pipeline has elevated permissions to push images and manifests. │
│  Mitigation: Service Principal scoped to minimum required roles. │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 5: ArgoCD → AKS API Server (management boundary)      │
│  ArgoCD has cluster-wide deploy permissions.                     │
│  Mitigation: ArgoCD AppProject limits to microservices ns only.  │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  BOUNDARY 6: Developer → GitHub → Azure DevOps (dev boundary)   │
│  Commit triggers pipeline; malicious commit = malicious build.   │
│  Mitigation: Branch protection, PR review, secret scanning.      │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Flows

| ID | Flow | Data Crosses Boundary | Contents | Trust |
|----|------|-----------------------|----------|-------|
| DF-1 | Developer → GitHub | Boundary 6 | Source code, K8s manifests | Low (any contributor) |
| DF-2 | GitHub → Azure DevOps (webhook) | Boundary 6 | Commit SHA, branch ref | Medium |
| DF-3 | Azure DevOps → ACR | Boundary 4 | Container images | High (Service Principal) |
| DF-4 | Azure DevOps → GitHub (CD manifest update) | Boundary 4/6 | K8s manifest YAML | High (bot PAT) |
| DF-5 | ArgoCD → GitHub (poll) | Boundary 5 | K8s manifest YAML | High (ArgoCD PAT) |
| DF-6 | ArgoCD → AKS API | Boundary 5 | Deployment specs, image refs | High (cluster admin) |
| DF-7 | AKS → ACR (image pull) | Boundary 4 | Container images | High (kubelet managed identity) |
| DF-8 | Internet → LoadBalancer → Pod | Boundary 1/2 | HTTP requests (no PII) | Untrusted |
| DF-9 | Key Vault → Azure DevOps pipeline | Boundary 4 | Secrets (ArgoCD password, PAT) | High (managed identity) |

---

## 4. Entry Points

| ID | Entry Point | Accessible By | Current Control |
|----|-------------|---------------|-----------------|
| EP-1 | Python-app LoadBalancer IP:80 | Entire Internet | None (no WAF, no rate limit) |
| EP-2 | Node.js-app LoadBalancer IP:80 | Entire Internet | None |
| EP-3 | .NET-app LoadBalancer IP:80 | Entire Internet | None |
| EP-4 | ArgoCD UI LoadBalancer IP:443 | Entire Internet | Password auth only |
| EP-5 | GitHub repository | Authenticated GitHub users | Branch protection + PR review |
| EP-6 | Azure DevOps portal | Authenticated DevOps users | AAD + MFA (assumed) |
| EP-7 | AKS API server | kubectl / ArgoCD / CI pipeline | K8s RBAC + AAD integration |
| EP-8 | Azure Key Vault | Service Principal / Managed Identity | Azure RBAC |

---

## 5. STRIDE Threat Analysis

### S — Spoofing

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| S-1 | ArgoCD server spoofed in CD pipeline | MITM between pipeline runner and ArgoCD LB IP; pipeline sends admin password to attacker | Low | Critical | Removed `--insecure`; using `--grpc-web`; add TLS cert check when production cert is provisioned | Verify pipeline YAML does not contain `--insecure` |
| S-2 | Container image substitution in ACR | Attacker with ACR write access replaces `python-app:1234` with malicious image | Very Low | Critical | Images pushed only via CI pipeline Service Principal; Trivy scan before push; immutable build-ID tags | Confirm ACR has no other write principals; review ACR access logs |
| S-3 | Pipeline bot impersonation | Leaked GitHub PAT allows attacker to push manifest changes as the pipeline bot | Low | High | PAT stored in Key Vault; access logged; PAT has minimum required scope (repo write only) | Review Key Vault access log; confirm PAT scope |

---

### T — Tampering

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| T-1 | Malicious K8s manifest committed to main | Attacker with GitHub write access modifies a deployment YAML to run a privileged container or mount the node filesystem | Low | Critical | Branch protection requires PR + review; Checkov blocks `privileged: true` in IaC gate; pre-commit hooks block on direct push to main | Verify branch protection settings in GitHub; confirm Checkov checks for `privileged` flag |
| T-2 | K8s manifest updated mid-pipeline by another actor | Race condition: a human commits directly to main between the CD pipeline's `git pull` and `git push` | Very Low | Medium | `git push` will fail on conflict; pipeline is re-triggered; `[skip ci]` tag prevents loop | Test with a concurrent commit |
| T-3 | Container image tampered after Trivy scan | A TOCTOU attack between scan and push | Very Low | High | Build and push are sequential in the same pipeline job on an ephemeral runner; no shared state between jobs| Confirm runner is ephemeral (hosted agent) |

---

### R — Repudiation

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| R-1 | ArgoCD admin actions not attributable | Multiple team members share the ArgoCD admin password; a destructive sync cannot be traced to a person | Medium | Medium | **Residual risk** — accepted for this academic project. In production: OIDC SSO so each user has their own identity | Accept + document |
| R-2 | Pipeline-initiated commits indistinguishable from human commits | Git log shows bot commits without a verifiable signature | Low | Low | Bot commit messages include pipeline run ID and `[bot]` suffix in author name | Review git log format after first CD run |

---

### I — Information Disclosure

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| I-1 | Secrets leaked in pipeline logs | Azure DevOps accidentally prints a masked variable (e.g., via `set -x` in a bash step) | Low | Critical | Key Vault secrets are never echoed; no `set -x` in pipeline scripts; Azure DevOps log masking active | Review all pipeline steps for `set -x`; verify Key Vault vars are masked in a test run |
| I-2 | ArgoCD UI exposes cluster topology | Anyone who reaches the ArgoCD LoadBalancer IP and bruteforces the admin password sees all deployed services, images, and namespaces | Medium | Medium | Admin password is strong and stored in Key Vault; no public documentation of ArgoCD IP | Rotate default password; verify ArgoCD IP is not in README or docs |
| I-3 | Application logs contain sensitive request data | HTTP request logs inadvertently capture query parameters or headers | Low | Low | Current microservices do not log request bodies; no PII in this demo application | Review app logging code before adding real data |
| I-4 | Container image layers expose build secrets | `docker build` caches secrets in an intermediate layer | Low | Medium | Multi-stage builds used; no `ARG` or `ENV` secrets in any Dockerfile | `docker history <image>` to verify no secrets in layers |

---

### D — Denial of Service

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| D-1 | HTTP flood on LoadBalancer IPs | Attacker sends sustained traffic to any of the three public IPs | Medium | High | **Residual risk** — no WAF or DDoS protection in this academic setup. Azure DDoS Basic is on by default (protects at L3/L4 only). Application-layer DDoS (L7) is unprotected. | Accept + document; add Azure WAF in production |
| D-2 | Runaway pod / CPU exhaustion | A bug causes a pod to consume all node CPU, starving other pods | Low | Medium | ResourceQuota + LimitRange enforced at namespace level; CPU limit set per container | Verify `kubectl describe resourcequota -n microservices` after apply |
| D-3 | Pipeline storm loops | CD pipeline commit re-triggers CI, which re-triggers CD in a loop | Low | Medium | `[skip ci]` in CD commit message; CI trigger scoped to `microservices/**` path, not `k8s/**` | Confirm CI trigger path excludes `k8s/`; test with a manifest-only commit |

---

### E — Elevation of Privilege

| ID | Threat | Attack Scenario | Likelihood | Impact | Mitigation | Owner | Verification |
|----|--------|-----------------|------------|--------|------------|-------|--------------|
| E-1 | Container breakout via root process | Compromised application process (running as root) writes to node filesystem or calls privileged syscalls | Low | Critical | All Dockerfiles use non-root user (UID 1001 or 1000); `runAsNonRoot: true`; `allowPrivilegeEscalation: false`; seccomp RuntimeDefault; drop ALL capabilities | `kubectl exec -it <pod> -- id` should return non-root UID |
| E-2 | Pod calls K8s API via auto-mounted SA token | Compromised pod queries K8s API to enumerate cluster or modify other resources | Low | High | `automountServiceAccountToken: false` on all pods and ServiceAccounts | `kubectl exec -it <pod> -- ls /var/run/secrets/kubernetes.io/serviceaccount` should return permission denied or empty |
| E-3 | ArgoCD escapes AppProject namespace scope | ArgoCD application configured to deploy outside `microservices` namespace | Very Low | High | `argocd/project.yaml` restricts destination namespace to `microservices` only | Verify AppProject YAML; attempt deploy to `default` namespace via ArgoCD — should be rejected |
| E-4 | CI Service Principal used beyond pipeline scope | Stolen Service Principal credentials used to modify Azure subscription resources directly | Very Low | Critical | Service Principal has only `AcrPush` on ACR and `Key Vault Secrets User` on Key Vault — not Contributor on the subscription | Review SP role assignments in Azure portal |

---

## 6. Residual Risks (Accepted for Academic Context)

| Risk ID | Description | Why Accepted | Compensating Control | Sign-off |
|---------|-------------|--------------|---------------------|---------|
| RR-1 | No WAF or L7 rate limiting on LoadBalancer IPs | Cost: Azure WAF is ~$40/month; not justified for a demo with no real traffic | Monitor Azure DDoS alerts; take services offline after demo |
| RR-2 | ArgoCD uses shared admin password (no SSO) | Azure AD OIDC integration requires Azure AD Premium licence | Strong password in Key Vault; rotate after every demo session |
| RR-3 | Services communicate over HTTP, not mTLS | mTLS requires a service mesh (Istio/Linkerd) — significant operational overhead for 3 demo services | NetworkPolicy blocks all inter-service traffic (services are independent, not a mesh) |
| RR-4 | No automated secret rotation | Key Vault rotation requires pipeline changes; out of scope for June deadline | Manually rotate PAT and ArgoCD password after project submission |
| RR-5 | No penetration test | Academic project; no sensitive data; no public users | All STRIDE mitigations implemented and verified; this model is the evidence |

---

## 7. Next Review Trigger

This model must be updated if any of the following occur:
- A new microservice is added
- External database or message queue is connected
- ArgoCD is configured for SSO
- Real user traffic or PII is introduced
- Any security incident or near-miss
