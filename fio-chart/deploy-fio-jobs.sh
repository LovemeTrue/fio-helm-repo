#!/bin/bash

set -e

# Define Helm chart info
CHART_NAME="fio-chart"
CHART_REPO="https://lovemetrue.github.io/fio-helm-repo/"
CHART_VERSION="0.1.0"
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
      --version "$CHART_VERSION" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  else
    helm install "$release" "$CHART_REPO/$CHART_NAME" \
      --version "$CHART_VERSION" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  fi

  # Wait for Job to be created
  job_name=""
  for i in {1..30}; do
    job_name=$(kubectl get jobs -n "$NAMESPACE" -l app=fio-job \
      -o jsonpath="{range .items[?(@.metadata.labels.helm\\.sh/release=='$release')]}{.metadata.name}{'\n'}{end}")
    [[ -n "$job_name" ]] && break
    sleep 2
  done

  [[ -z "$job_name" ]] && echo "[ERROR] No job found for release $release" && continue

  # Wait for job to complete
  if ! kubectl wait --for=condition=complete --timeout=180s job/"$job_name" -n "$NAMESPACE"; then
    echo "[ERROR] Job $job_name did not complete in time"
    continue
  fi

  # Get logs
  pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" \
    -o jsonpath="{.items[0].metadata.name}")
  echo "[INFO] Saving logs for node $node to $log_file"
  kubectl logs "$pod_name" -n "$NAMESPACE" | tee "$log_file"

done

echo "✅ All done. Logs saved in fio-results/"