# 📦 FIO Benchmark Helm Chart

This Helm chart (`fio-chart`) deploys a disk benchmarking job using [`fio`](https://github.com/axboe/fio) to every node in your Kubernetes cluster (including masters and workers).  
It is designed for both **open/public clusters** and **air-gapped / private environments**.

---

## 🚀 Features

- Deploys a **Kubernetes pod per node** with `fio`
- Supports custom `fio` arguments
- Runs automatically on **all nodes**
- Compatible with **Helm Hooks** (`post-install`, `post-upgrade`)
- Works in both **connected and disconnected** environments
- Collects logs into per-node files

---

## 📁 Directory structure
```
fio-helm-repo/
├── index.yaml                    # Helm repo index
├── fio-chart-0.1.0.tgz          # Helm chart package
├── fio-chart/                   # Source chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── templates/
│   │   └── fio-job.yaml
│   └── .helmignore
├── fio-results/                 # Benchmark logs (created by script)
└── deploy-fio-jobs.sh           # Bash script to deploy jobs on all nodes
```

---

## 🌍 Public / connected cluster usage

### 1. 🛠️ To start wget sh script ->:

1. Download
```
wget http://lovemetrue.github.io/fio-helm-repo/fio-chart/deploy-fio-jobs.sh
```
2. ## Change the mode
```
chmod -R 777 deploy-fio-jobs.sh
```
3. ### And run by typing this command:

```bash
./deploy-fio-jobs.sh
```

### 1. Download chart manually (from a connected machine)

```bash
wget https://lovemetrue.github.io/fio-helm-repo/fio-chart-0.1.0.tgz
```

### 2. Transfer the file to your air-gapped cluster

(e.g. using USB, SCP, rsync, etc.)

### 3. Install the chart from local .tgz file (per node)
```bash
helm install fio-master ./fio-chart-0.1.0.tgz \
  --set global.nodeSelector."kubernetes\.io/hostname"=master-node-name
```

## 📬 Contact & License

Feel free to contribute or raise issues. 
