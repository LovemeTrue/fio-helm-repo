#!/bin/bash
set -e

CHART_NAME="fio-chart"
CHART_REPO="fio"
RELEASE_NAME="fio-daemonset"
NAMESPACE="default"
OUTPUT_DIR="fio-results/multi-node-disk-analyzes"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Создаем директории для результатов
mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/json"

echo "[INFO] Starting disk analysis at $TIMESTAMP"

# Установка/обновление Helm релиза
if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "[INFO] Upgrading Helm release..."
  helm upgrade "$RELEASE_NAME" "$CHART_REPO/$CHART_NAME" \
    --namespace "$NAMESPACE"
else
  echo "[INFO] Installing Helm release..."
  helm install "$RELEASE_NAME" "$CHART_REPO/$CHART_NAME" \
    --namespace "$NAMESPACE"
fi

# Ожидаем запуска всех подов
echo "[INFO] Waiting for pods to start..."
sleep 10
kubectl wait --for=condition=Ready --timeout=300s -n "$NAMESPACE" pod -l app.kubernetes.io/name=fio-chart

# Собираем результаты с каждой ноды
echo "[INFO] Collecting results from nodes..."
nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for node in $nodes; do
  safe_node_name=$(echo "$node" | tr -cd '[:alnum:]-_')
  node_output_dir="$OUTPUT_DIR/json/$safe_node_name"
  mkdir -p "$node_output_dir"
  
  # Получаем путь к результатам на ноде
  node_path="/root/fio-results"
  
  # Копируем файлы с ноды
  if kubectl cp "$node":$node_path/ $node_output_dir/ >/dev/null 2>&1; then
    echo "[OK] Results copied from node: $node"
  else
    echo "[WARN] Failed to copy results from node: $node"
  fi

  # Собираем информацию о ноде
  kubectl describe node "$node" > "$OUTPUT_DIR/${safe_node_name}-node-info.txt"
done

# Очистка
echo "[INFO] Uninstalling Helm release..."
helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"

echo "✅ All done. Results saved in $OUTPUT_DIR/"
echo "  - Node info files: $(ls $OUTPUT_DIR/*-node-info.txt | wc -l)"
echo "  - JSON results: $(find $OUTPUT_DIR/json -type f | wc -l)"