# Log Analytics KQL Queries

Run these queries in **Azure Portal → Log Analytics Workspace → Logs**.

Each query has a purpose, a time range, and what the output means.

---

## 1. Pod Restarts in the Last Hour

**When to use:** You got a pod-restart alert. This tells you which pod, which container, and how many times.

```kql
KubePodInventory
| where Namespace == "microservices"
| where TimeGenerated > ago(1h)
| where PodRestartCount > 0
| project TimeGenerated, PodName = Name, ContainerName, PodRestartCount, PodStatus
| order by PodRestartCount desc
```

---

## 2. Container Logs — Last 100 Lines From a Specific Service

**When to use:** A pod is crashing or returning errors. Replace `python-app` with `nodejs-app` or `dotnet-app`.

```kql
ContainerLog
| where TimeGenerated > ago(30m)
| where ContainerID has "python-app"
| project TimeGenerated, LogEntry
| order by TimeGenerated desc
| take 100
```

---

## 3. HTTP 5xx Errors Across All Services

**When to use:** Users are reporting errors. This shows the volume and timing of server-side errors.

```kql
ContainerLog
| where TimeGenerated > ago(1h)
| where LogEntry matches regex " 5[0-9]{2} "
| summarize ErrorCount = count() by bin(TimeGenerated, 1m), ContainerID
| order by TimeGenerated desc
```

---

## 4. Node CPU and Memory — Last 30 Minutes

**When to use:** You got a node CPU/memory alert. This shows which node is the problem.

```kql
Perf
| where TimeGenerated > ago(30m)
| where ObjectName == "K8SNode"
| where CounterName in ("cpuUsagePercentage", "memoryWorkingSetPercentage")
| summarize AvgValue = avg(CounterValue) by Computer, CounterName, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

---

## 5. ArgoCD Sync Events — Last 2 Hours

**When to use:** You want to see when ArgoCD last successfully synced and whether any errors occurred.

```kql
ContainerLog
| where TimeGenerated > ago(2h)
| where ContainerID has "argocd"
| where LogEntry contains "sync" or LogEntry contains "Sync"
| project TimeGenerated, LogEntry
| order by TimeGenerated desc
| take 50
```

---

## 6. Failed Image Pulls (ImagePullBackOff)

**When to use:** Pods are not starting after a deployment. Likely ACR authentication issue or image tag does not exist.

```kql
KubeEvents
| where TimeGenerated > ago(1h)
| where Namespace == "microservices"
| where Reason in ("Failed", "BackOff", "ErrImagePull", "ImagePullBackOff")
| project TimeGenerated, Name, Reason, Message
| order by TimeGenerated desc
```

---

## 7. All Kubernetes Events in Microservices Namespace

**When to use:** Something changed and you don't know what. This gives a full timeline.

```kql
KubeEvents
| where TimeGenerated > ago(1h)
| where Namespace == "microservices"
| project TimeGenerated, Name, Reason, Message, Type
| order by TimeGenerated desc
```

---

## 8. Pipeline-Triggered Deployments (Audit Trail)

**When to use:** You need to answer: what deployed when, and did it succeed?

```kql
KubePodInventory
| where Namespace == "microservices"
| where TimeGenerated > ago(24h)
| where ContainerImage has "acrgitopsproject"
| summarize LastSeen = max(TimeGenerated) by PodName = Name, ContainerImage
| order by LastSeen desc
```

The `ContainerImage` field shows the exact build-ID tag that is running, linking each
pod back to a specific Azure DevOps pipeline run.

---

## 9. Security — Unexpected Processes Inside a Container

**When to use:** You suspect a container has been compromised and something unexpected is running.

```kql
ContainerLog
| where TimeGenerated > ago(1h)
| where Namespace == "microservices"
| where LogEntry contains "exec" or LogEntry contains "/bin/sh" or LogEntry contains "/bin/bash"
| project TimeGenerated, ContainerID, LogEntry
| order by TimeGenerated desc
```

---

## Saving Queries

To save a query for reuse:
1. Paste the query into Log Analytics
2. Click **Save → Save as query**
3. Name it and assign to the `microservices` category
4. Saved queries are available to all team members in the workspace
