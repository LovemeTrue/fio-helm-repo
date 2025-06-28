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

### 1. 🛠️ Get started with wgetting sh script:

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

### 2. 🛡️ Running fio-chart in a Closed (Air-Gapped) Kubernetes Cluster

### This guide will show you how to:
- Download the required .tgz Helm chart and shell script
- Transfer them into the air-gapped environment
- Set permissions
- Run the test and collect logs

```bash
wget https://lovemetrue.github.io/fio-helm-repo/fio-chart-0.1.0.tgz
wget https://lovemetrue.github.io/fio-helm-repo/fio-chart/deploy-fio-offline.sh
```

### 3. Transfer the file to your air-gapped cluster and change mode:

(e.g. using USB, SCP, rsync, etc.)

```
chmod +x deploy-fio-offline.sh
```

### 4. Run the sh script to analyze nodes with fio:
```bash
./deploy-fio-offline.sh
```

## 📬 Contact & License

Feel free to contribute or raise issues. 
