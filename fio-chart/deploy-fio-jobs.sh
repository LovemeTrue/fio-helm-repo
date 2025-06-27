
#!/bin/bash

set -e

CHART_NAME="fio-chart"
CHART_REPO="https://lovemetrue.github.io/fio-helm-repo"
CHART_VERSION="0.1.0"
RELEASE_PREFIX="fio"
NAMESPACE="default"

mkdir -p fio-results

echo "[INFO] Получаем список нод..."
nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

for node in $nodes; do
  release="${RELEASE_PREFIX}-${node}"
  log_file="fio-results/${node}.log"

  echo "=============================="
  echo "[INFO] Обрабатываем ноду: $node"
  echo "[INFO] Release: $release"

  # Установка или обновление Helm-релиза
  if helm status "$release" -n "$NAMESPACE" &>/dev/null; then
    echo "[INFO] Обновляем Helm release (перезапуск Job)..."
    helm upgrade "$release" "$CHART_REPO/$CHART_NAME" \
      --version "$CHART_VERSION" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  else
    echo "[INFO] Устанавливаем Helm release..."
    helm install "$release" "$CHART_REPO/$CHART_NAME" \
      --version "$CHART_VERSION" \
      --namespace "$NAMESPACE" \
      --set global.nodeSelector."kubernetes\\.io/hostname"="$node"
  fi

  echo "[INFO] Ожидаем создание Job..."

  # Подождем появления Job
  job_name=""
  for i in {1..30}; do
    job_name=$(kubectl get jobs -n "$NAMESPACE" -l app=fio-job -o jsonpath="{range .items[?(@.metadata.labels.helm\\.sh/release=='$release')]}{.metadata.name}{'\n'}{end}")
    if [[ -n "$job_name" ]]; then
      echo "[INFO] Найден Job: $job_name"
      break
    fi
    sleep 2
  done

  if [[ -z "$job_name" ]]; then
    echo "[ERROR] Не удалось найти Job для release $release"
    continue
  fi

  echo "[INFO] Ожидаем завершение Job: $job_name"

  # Ждём завершения Job
  kubectl wait --for=condition=complete --timeout=180s job/"$job_name" -n "$NAMESPACE" || {
    echo "[ERROR] Job не завершился вовремя"
    continue
  }

  # Получаем имя pod-а
  pod_name=$(kubectl get pods -n "$NAMESPACE" -l job-name="$job_name" -o jsonpath="{.items[0].metadata.name}")
  echo "[INFO] Под: $pod_name"

  # Логи Job
  echo "[INFO] Собираем результат fio с $node..."
  kubectl logs "$pod_name" -n "$NAMESPACE" | tee "$log_file"
  echo "[INFO] Результат сохранён в: $log_file"

done

echo "✅ Готово. Все логи лежат в папке fio-results/"