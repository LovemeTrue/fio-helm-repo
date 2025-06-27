REPO_NAME=fio
REPO_URL=https://lovemetrue.github.io/fio-helm-repo
SCRIPT_URL=$(REPO_URL)/fio-chart/deploy-fio-jobs.sh
SCRIPT_NAME=deploy-fio-jobs.sh

.PHONY: all setup download-script run clean

all: setup download-script run

setup:
	@echo "[1/4] Adding Helm repo..."
	helm repo add $(REPO_NAME) $(REPO_URL) || true
	@echo "[2/4] Updating Helm repo..."
	helm repo update

download-script:
	@echo "[3/4] Downloading script from $(SCRIPT_URL)..."
	wget -q -O $(SCRIPT_NAME) $(SCRIPT_URL)
	chmod +x $(SCRIPT_NAME)

run:
	@echo "[4/4] Running script..."
	./$(SCRIPT_NAME)

clean:
	rm -f $(SCRIPT_NAME)