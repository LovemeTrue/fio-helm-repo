#!/bin/bash

set -e

RELEASE_NAME="fio-daemon"
CHART_NAME="fio-chart"
CHART_REPO="fio"
REPO_URL="https://lovemetrue.github.io/fio-helm-repo"
NAMESPACE="default"
LOG_DIR="fio-results"

mkdir -p "$LOG_DIR"

# Check for dependencies
for bin in helm kubectl; do
  if ! command -v $bin &> /dev/null; then
    echo "[ERROR] $bin is not installed. Please install it first."
    exit 1
  fi
done

echo "[INFO] Adding Helm repo..."
helm repo add "$CHART_REPO" "$REPO_URL" || true
sleep 2
helm repo update
sleep 2

echo "[INFO] Installing/upgrading DaemonSet..."
helm upgrade --install "$RELEASE_NAME" "$CHART_REPO/$CHART_NAME" --namespace "$NAMESPACE"
sleep 2

echo "[INFO] Waiting for fio-daemon pods to be Ready..."
kubectl wait --for=condition=Ready pods -l app=fio-daemon -n "$NAMESPACE" --timeout=180s || true

echo "[INFO] Collecting logs..."

nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for node in $nodes; do
  echo "------------------------------"
  echo "[INFO] Checking node: $node"

  pod=$(kubectl get pods -n "$NAMESPACE" -l app=fio-daemon \
    -o jsonpath="{range .items[?(@.spec.nodeName=='$node')]}{.metadata.name}{'\n'}{end}" | head -n1)

  if [[ -z "$pod" ]]; then
    echo "[WARN] No pod found for $node"
    continue
  fi

  echo "[INFO] Waiting for pod $pod to finish running fio..."

  # Wait up to 500 seconds for container to terminate (fio must exit)
  for i in {1..350}; do
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

echo "[INFO] Cleaning up Helm release and repo..."
helm delete "$RELEASE_NAME" --namespace "$NAMESPACE" || true
helm repo remove "$CHART_REPO" || true

echo "✅ Done. Logs are saved in $LOG_DIR/"