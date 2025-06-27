#!/bin/bash

set -e

RELEASE_NAME="fio-daemon"
CHART_NAME="fio-chart"
CHART_REPO="fio"
NAMESPACE="default"
LOG_DIR="fio-results/daemon-logs"

mkdir -p "$LOG_DIR"

echo "[INFO] Installing/upgrading DaemonSet..."
helm upgrade --install "$RELEASE_NAME" "$CHART_REPO/$CHART_NAME" \
  --namespace "$NAMESPACE" \
  --create-namespace

echo "[INFO] Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods -l app=fio-daemon -n "$NAMESPACE" --timeout=180s || true

echo "[INFO] Collecting logs..."

nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for node in $nodes; do
  pod=$(kubectl get pods -n "$NAMESPACE" -l app=fio-daemon \
    -o jsonpath="{range .items[?(@.spec.nodeName=='$node')]}{.metadata.name}{'\n'}{end}" | head -n1)

  if [[ -z "$pod" ]]; then
    echo "[WARN] No pod found on $node"
    continue
  fi

  log_file="$LOG_DIR/${node}.log"
  echo "[INFO] Saving logs from $pod → $log_file"
  kubectl logs "$pod" -n "$NAMESPACE" > "$log_file"
done

echo "✅ Done. Logs are in $LOG_DIR/"