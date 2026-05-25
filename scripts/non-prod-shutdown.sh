#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# non-prod-shutdown.sh
#
# Stop or start the AKS cluster to avoid paying for idle compute.
# Stopping the cluster powers down all agent nodes. The cluster control
# plane continues to run (no charge for it under the free tier).
#
# Usage:
#   ./scripts/non-prod-shutdown.sh stop    # Power down all nodes
#   ./scripts/non-prod-shutdown.sh start   # Bring nodes back online
#
# Prerequisites: az CLI installed and logged in (az login)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

RESOURCE_GROUP="rg-gitops-project"
CLUSTER_NAME="aks-gitops-cluster"
ACTION="${1:-}"

usage() {
  echo "Usage: $0 [stop|start]"
  echo ""
  echo "  stop  — Powers down AKS nodes. Saves ~\$90/month while stopped."
  echo "          ACR, Key Vault, and networking continue to accrue cost."
  echo "  start — Restores nodes and waits until all are Ready."
  exit 1
}

check_prerequisites() {
  if ! command -v az &>/dev/null; then
    echo "[ERROR] Azure CLI not found. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
  fi

  if ! az account show &>/dev/null; then
    echo "[ERROR] Not logged in to Azure. Run: az login"
    exit 1
  fi
}

stop_cluster() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stopping AKS cluster: $CLUSTER_NAME"
  echo "  Resource group : $RESOURCE_GROUP"
  echo "  Estimated saving: ~\$90/month while stopped"
  echo ""

  az aks stop \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --no-wait

  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Stop command issued."
  echo "  Nodes will reach 'Stopped' state in ~3–5 minutes."
  echo "  ArgoCD and all pods will be unavailable until you run: $0 start"
}

start_cluster() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Starting AKS cluster: $CLUSTER_NAME"
  echo ""

  az aks start \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME"

  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] Cluster started. Waiting for nodes to become Ready..."

  # Get credentials in case context is stale
  az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

  kubectl wait node \
    --for=condition=Ready \
    --all \
    --timeout=300s

  echo ""
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] All nodes ready."
  kubectl get nodes
  echo ""
  echo "ArgoCD may take ~2 minutes to re-establish sync after cluster start."
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_prerequisites

case "$ACTION" in
  stop)  stop_cluster  ;;
  start) start_cluster ;;
  *)     usage         ;;
esac
