#!/bin/bash

set -e

CHART_NAME="fio-chart"
CHART_REPO="fio"
RELEASE_PREFIX="fio"
NAMESPACE="default"
OUTPUT_DIR="multi-node-disk-analyzes"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Создаем директории для результатов
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/logs"
mkdir -p "$OUTPUT_DIR/json"

echo "[INFO] Starting disk analysis at $TIMESTAMP"
echo "[INFO] Getting list of nodes..."
nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

if [[ -z "$nodes" ]]; then
  echo "[ERROR] No nodes found"
  exit 1
fi

for node in $nodes; do
  # Очищаем имя ноды для использования в файлах
  safe_node_name=$(echo "$node" | tr -cd '[:alnum:]-_')
  release="${RELEASE_PREFIX}-${safe_node_name}"
  log_file="$OUTPUT_DIR/logs/${safe_node_name}.log"
  json_file="$OUTPUT_DIR/json/${safe_node_name}-${TIMESTAMP}.json"
  
  echo "=============================="
  echo "[INFO] Processing node: $node"
  echo "[INFO] Safe node name: $safe_node_name"
  echo "[INFO] Helm release: $release"
  echo "[INFO] Log file: $log_file"
  echo "[INFO] JSON file: $json_file"

  # Проверяем taints
  if kubectl describe node "$node" | grep -q "NoSchedule"; then
    echo "[WARN] Node $node is tainted (NoSchedule)"
  fi

  # Устанавливаем или обновляем Helm release
  if helm status "$release" -n "$NAMESPACE" &>/dev/null; then
    echo "[INFO] Upgrading Helm release..."
    helm upgrade "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node" \
      --set global.fioArgs="--name=disk-test --filename=/tmp/fio-test.tmp --size=256M --bs=4k --rw=randread --iodepth=16 --runtime=15 --numjobs=2 --time_based --group_reporting --output-format=json --output=$json_file"
  else
    echo "[INFO] Installing Helm release..."
    helm install "$release" "$CHART_REPO/$CHART_NAME" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node" \
      --set global.fioArgs="--name=disk-test --filename=/tmp/fio-test.tmp --size=256M --bs=4k --rw=randread --iodepth=16 --runtime=15 --numjobs=2 --time_based --group_reporting --output-format=json --output=$json_file"
  fi

  # Ожидаем запуска пода
  echo "[INFO] Waiting for pod to start on node $node..."
  sleep 10

  # Ищем связанный pod
  echo "[INFO] Searching for pod scheduled on node $node..."
  pod=$(kubectl get pods -n "$NAMESPACE" \
    -l app=fio-job \
    -o jsonpath="{range .items[?(@.spec.nodeName=='$node')]}{.metadata.name}{'\n'}{end}" \
    | grep "^fio-" | tail -n1)

  if [[ -z "$pod" ]]; then
    echo "[ERROR] No pod found on node $node. Skipping log collection."
    continue
  fi

  echo "[INFO] Found pod: $pod"

  # Ожидаем завершения работы пода
  echo "[INFO] Waiting for job completion on node $node..."
  if kubectl wait --for=condition=complete --timeout=300s -n "$NAMESPACE" job.batch/"${release}"-*; then
    echo "[INFO] Job completed successfully on node $node"
  else
    echo "[WARN] Job did not complete in time or failed on node $node"
  fi

  # Собираем логи
  echo "[INFO] Collecting logs from pod $pod..."
  if ! kubectl logs "$pod" -n "$NAMESPACE" > "$log_file"; then
    echo "[ERROR] Failed to collect logs from pod $pod"
    continue
  fi

  # Проверяем наличие JSON-результатов
  if kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "test -f $json_file && echo 'exists'"; then
    echo "[INFO] Copying JSON results from pod..."
    kubectl cp -n "$NAMESPACE" "$pod:$json_file" "$json_file"
    echo "[INFO] JSON results saved to $json_file"
  else
    echo "[WARN] JSON results file not found in pod"
  fi

  # Сохраняем дополнительную информацию о ноде
  node_info_file="$OUTPUT_DIR/${safe_node_name}-node-info.txt"
  echo "[INFO] Collecting node info for $node..."
  kubectl describe node "$node" > "$node_info_file"
  echo "[INFO] Node info saved to $node_info_file"
done

echo "✅ All done. Results saved in $OUTPUT_DIR/"
echo "Summary:"
echo "  - Node info files: $(ls $OUTPUT_DIR/*-node-info.txt | wc -l)"
echo "  - Log files: $(ls $OUTPUT_DIR/logs | wc -l)"
echo "  - JSON results: $(ls $OUTPUT_DIR/json | wc -l)"