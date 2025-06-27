#!/bin/bash

set -e

# Define Helm chart info
CHART_NAME="fio-chart-0.1.0.tgz"
CHART_REPO="https://lovemetrue.github.io/fio-helm-repo/"
RELEASE_PREFIX="fio"
NAMESPACE="default"

# Create folder for logs
mkdir -p fio-results

# Get list of all nodes
nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# Handle empty or single-node cluster
count=$(echo "$nodes" | wc -l)
if [[ $count -eq 0 ]]; then
  echo "[ERROR] No nodes found!"
  exit 1
fi
if [[ $count -eq 1 ]]; then
  echo "[INFO] Single-node cluster detected: $nodes"
fi

# Loop over nodes
for node in $nodes; do
  release="${RELEASE_PREFIX}-${node}"
  log_file="fio-results/${node}.log"

  echo "=============================="
  echo "[INFO] Working on node: $node"

  # Warn if node is tainted with NoSchedule (e.g. master)
  if kubectl describe node "$node" | grep -q "NoSchedule"; then
    echo "[WARN] Node $node is tainted with NoSchedule — may block pod scheduling"
  fi

  # Install or upgrade Helm release per node
  if helm status "$release" -n "$NAMESPACE" &>/dev/null; then
    helm upgrade "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  else
    helm install "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  fi

  # Wait for Job to be created
  echo "[INFO] Waiting for Job to be created..."
  job_name=""
  for i in {1..30}; do
    job_name=$(kubectl get jobs -n "$NAMESPACE" -l app=fio-job \
      -o jsonpath="{range .items[*]}{.metadata.name}{'\n'}{end}" | grep "$release" || true)
    [[ -n "$job_name" ]] && break
    sleep 2
  done

  if [[ -z "$job_name" ]]; then
    echo "[ERROR] Job for release $release not found"
    continue
  fi

  echo "[INFO] Job found: $job_name"
  echo "[INFO] Waiting for job completion (180s max)..."
  if ! kubectl wait --for=condition=complete --timeout=180s job/"$job_name" -n "$NAMESPACE"; then
    echo "[ERROR] Job $job_name did not complete in time"
    continue
  fi

  echo "[INFO] Job completed. Retrieving logs..."
  pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" \
    -o jsonpath="{.items[0].metadata.name}")

  if [[ -z "$pod_name" ]]; then
    echo "[ERROR] Pod for job $job_name not found"
    continue
  fi

  echo "[INFO] Saving logs to $log_file"
  if ! kubectl logs "$pod_name" -n "$NAMESPACE" > "$log_file"; then
    echo "[WARN] Failed to get logs from pod $pod_name"
    continue
  fi

  echo "[INFO] Log saved: $log_file"

done

echo "✅ All jobs processed. Logs are in fio-results/"