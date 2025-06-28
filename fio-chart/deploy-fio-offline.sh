#!/bin/bash

set -e

RELEASE_NAME="fio-daemon"
CHART_TGZ="./fio-chart-0.1.0.tgz"
NAMESPACE="default"
LOG_DIR="fio-results"

mkdir -p "$LOG_DIR"

# Dependency check
for bin in helm kubectl; do
  if ! command -v $bin &> /dev/null; then
    echo "[ERROR] $bin is not installed. Please install it first."
    exit 1
  fi
done

# Check for chart presence
if [[ ! -f "$CHART_TGZ" ]]; then
  echo "[ERROR] Chart file $CHART_TGZ not found."
  exit 1
fi

echo "[INFO] Installing/upgrading local chart $CHART_TGZ..."
helm upgrade --install "$RELEASE_NAME" "$CHART_TGZ" --namespace "$NAMESPACE" --create-namespace
sleep 2

echo "[INFO] Waiting for fio-daemon pods to become Ready..."
kubectl wait --for=condition=Ready pods -l app=fio-daemon -n "$NAMESPACE" --timeout=180s || true

echo "[INFO] Collecting logs from all nodes..."

nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for node in $nodes; do
  echo "------------------------------"
  echo "[INFO] Checking node: $node"

  pod=$(kubectl get pods -n "$NAMESPACE" -l app=fio-daemon \
    -o jsonpath="{range .items[?(@.spec.nodeName=='$node')]}{.metadata.name}" | head -n1)

  if [[ -z "$pod" ]]; then
    echo "[WARN] No pod found for $node"
    continue
  fi

  echo "[INFO] Waiting for pod $pod to complete fio..."

  # Wait up to 1280 seconds for container to terminate
  for i in {1..180}; do
    state=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath="{.status.containerStatuses[0].state.terminated.reason}" 2>/dev/null || echo "")
    if [[ "$state" == "Completed" ]]; then
      echo "[INFO] Pod $pod has completed"
      break
    fi
    sleep 2
  done

  log_file="$LOG_DIR/${node}.log"
  echo "[INFO] Fetching logs from $pod → $log_file"
  kubectl logs "$pod" -n "$NAMESPACE" > "$log_file" || echo "[WARN] Failed to get logs from $pod"
done

echo "[INFO] Cleaning up local Helm release..."
helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" || true

echo "✅ Done. Logs saved in $LOG_DIR/"