#!/bin/bash

set -e

CHART_NAME="fio-chart"
CHART_REPO="fio"
RELEASE_PREFIX="fio"
NAMESPACE="default"
OUTPUT_DIR="fio-results/multi-node-disk-analyzes"

mkdir -p "$OUTPUT_DIR"

echo "[INFO] Getting list of nodes..."
nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

if [[ -z "$nodes" ]]; then
  echo "[ERROR] No nodes found"
  exit 1
fi

for node in $nodes; do
  release="${RELEASE_PREFIX}-${node}"
  log_file="$OUTPUT_DIR/${node}.log"

  echo "=============================="
  echo "[INFO] Processing node: $node"
  echo "[INFO] Helm release: $release"

  # Warn if tainted
  if kubectl describe node "$node" | grep -q "NoSchedule"; then
    echo "[WARN] Node $node is tainted (NoSchedule)"
  fi

  # Install or upgrade Helm release
  if helm status "$release" -n "$NAMESPACE" &>/dev/null; then
    echo "[INFO] Upgrading Helm release..."
    helm upgrade "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  else
    echo "[INFO] Installing Helm release..."
    helm install "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  fi

  # Try to find related pod
  echo "[INFO] Searching for pod (fio-*) scheduled on node $node..."
  pod=$(kubectl get pods -n "$NAMESPACE" \
    -l app=fio-job \
    -o jsonpath="{range .items[?(@.spec.nodeName=='$node')]}{.metadata.name}{'\n'}{end}" \
    | grep "^fio-" | tail -n1)

  if [[ -z "$pod" ]]; then
    echo "[WARN] No pod found on node $node. Skipping log collection."
    continue
  fi

  echo "[INFO] Found pod: $pod. Collecting logs..."
  if ! kubectl logs "$pod" -n "$NAMESPACE" > "$log_file"; then
    echo "[ERROR] Failed to collect logs from pod $pod"
    continue
  fi

  echo "[INFO] Logs saved to $log_file"
done

echo "✅ All done. Logs saved in $OUTPUT_DIR/"