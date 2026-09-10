#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Production Cloud Platform
# Disaster Recovery Bootstrap Script
#
# Ubuntu -> Docker -> kubectl -> Kind -> Helm
#        -> Git clone -> telemetry-system namespace -> ArgoCD
#        -> Prometheus / Grafana -> Loki -> Promtail
#        -> ArgoCD Application sync -> Production Cloud Platform
#
# Based on the actual successful manual recovery history.
#
# Tested stack:
#   Kubernetes: v1.37
#   Kind:       v0.33.0
#   Loki chart: grafana-community/loki 18.12.1
#
# ============================================================


# ============================================================
# Usage
#
# The script may be stored anywhere outside the repository.
#
# Recommended location:
#   $HOME/bootstrap-disaster-recovery.sh
#
# The script expects the Git repository to be created at:
#   $HOME/production-cloud-platform/
#
# After cloning the repository, the script can also be run from
# the repository root:
#   ./bootstrap-disaster-recovery.sh
#
# For a clean disaster-recovery test, keep the script outside
# $HOME/production-cloud-platform before running it,
# so the repository directory can be created from scratch.
#
# ============================================================


# ============================================================
# Configuration
# ============================================================

REPO_URL="https://github.com/av-crypto-security/production-cloud-platform.git"
REPO_DIR="$HOME/production-cloud-platform"

KIND_VERSION="v0.33.0"
KIND_CLUSTER_NAME="telemetry"

K8S_MINOR_VERSION="v1.37"

ARGOCD_NAMESPACE="argocd"
MONITORING_NAMESPACE="monitoring"
TELEMETRY_NAMESPACE="telemetry-system"

LOKI_CHART="grafana-community/loki"
LOKI_VERSION="18.12.1"


# ============================================================
# Helpers
# ============================================================

retry_curl() {
    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 5 \
        --retry-delay 5 \
        --retry-max-time 300 \
        "$@"
}


apt_update() {
    sudo apt-get \
        -o Acquire::Retries=5 \
        update
}


# ============================================================
# Header
# ============================================================

echo
echo "============================================================"
echo " Production Cloud Platform - Disaster Recovery Bootstrap"
echo "============================================================"
echo


# ============================================================
# 1. System prerequisites
# ============================================================

echo "[1/10] Installing system prerequisites..."

apt_update

sudo apt-get upgrade -y

sudo apt-get install -y \
    ca-certificates \
    curl \
    git \
    gpg \
    jq \
    unzip \
    wget

echo
echo "System prerequisites installed."
echo


# ============================================================
# 2. Docker
# ============================================================

echo "[2/10] Installing Docker..."

sudo install -m 0755 -d /etc/apt/keyrings


echo "Configuring Docker repository..."

DOCKER_KEY_TMP="$(mktemp)"

retry_curl \
    "https://download.docker.com/linux/ubuntu/gpg" \
    -o "$DOCKER_KEY_TMP"

sudo gpg \
    --dearmor \
    --yes \
    -o /etc/apt/keyrings/docker.gpg \
    "$DOCKER_KEY_TMP"

rm -f "$DOCKER_KEY_TMP"

sudo chmod a+r /etc/apt/keyrings/docker.gpg


echo "deb [arch=$(dpkg --print-architecture) \
signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null


apt_update


if dpkg-query -W -f='${Status}' docker-ce 2>/dev/null |
    grep -q "install ok installed"; then

    echo "Docker packages are already installed."

else

    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

fi


sudo systemctl enable --now docker


echo
echo "Docker version:"
sudo docker version


echo
echo "Docker Compose version:"
sudo docker compose version


echo
echo "Running Docker hello-world..."

sudo docker run --rm hello-world


echo
echo "Adding $USER to docker group..."

sudo usermod -aG docker "$USER"


echo
echo "Docker installation completed."
echo


# ============================================================
# 3. kubectl
# ============================================================

echo "[3/10] Installing kubectl..."


sudo mkdir -p -m 755 /etc/apt/keyrings


K8S_KEY_TMP="$(mktemp)"

retry_curl \
    "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/Release.key" \
    -o "$K8S_KEY_TMP"

sudo gpg \
    --dearmor \
    --yes \
    -o /etc/apt/keyrings/kubernetes-apt-keyrings.gpg \
    "$K8S_KEY_TMP"

rm -f "$K8S_KEY_TMP"

sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyrings.gpg


echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyrings.gpg] \
https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/ /" |
sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null


apt_update


if command -v kubectl >/dev/null 2>&1; then

    echo "kubectl is already installed."

else

    sudo apt-get install -y kubectl

fi


echo
echo "kubectl:"
kubectl version --client
echo


# ============================================================
# 4. Kind
# ============================================================

echo "[4/10] Installing Kind ${KIND_VERSION}..."


if command -v kind >/dev/null 2>&1; then

    echo "Kind is already installed."

else

    retry_curl \
        "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" \
        -o /tmp/kind

    chmod +x /tmp/kind

    sudo mv /tmp/kind /usr/local/bin/kind

fi


echo
kind version
echo


# ============================================================
# 5. Create Kubernetes cluster
# ============================================================

echo "[5/10] Creating Kind cluster..."


if kind get clusters 2>/dev/null |
    grep -qx "$KIND_CLUSTER_NAME"; then

    echo "Kind cluster '$KIND_CLUSTER_NAME' already exists."

else

    echo
    echo "Creating Kind cluster using docker group..."

    sg docker -c \
        "kind create cluster --name '$KIND_CLUSTER_NAME'"

fi


echo
kubectl get nodes
echo


# ============================================================
# 6. Helm
# ============================================================

echo "[6/10] Installing Helm..."


if command -v helm >/dev/null 2>&1; then

    echo "Helm is already installed."

else

    retry_curl \
        "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" \
        -o /tmp/get_helm.sh

    chmod 700 /tmp/get_helm.sh

    /tmp/get_helm.sh

fi


echo
helm version
echo


# ============================================================
# 7. Clone Production Cloud Platform
# ============================================================

echo "[7/10] Getting Production Cloud Platform repository..."


if [[ -d "$REPO_DIR/.git" ]]; then

    echo "Repository already exists: $REPO_DIR"

else

    if [[ -d "$REPO_DIR" ]] &&
       [[ -n "$(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then

        echo
        echo "ERROR: $REPO_DIR exists and is not an empty Git repository."
        echo
        echo "Please move the bootstrap script outside the repository directory."
        echo
        echo "Expected layout:"
        echo "  $HOME/bootstrap-disaster-recovery.sh"
        echo "  $HOME/production-cloud-platform/"
        echo
        exit 1

    fi

    git clone "$REPO_URL" "$REPO_DIR"

fi


cd "$REPO_DIR"


echo
echo "Repository:"
git status --short


echo
echo "Running Helm lint..."

helm lint ./helm/production-cloud-platform

echo


# ============================================================
# 8. ArgoCD
# ============================================================

echo "[8/10] Installing ArgoCD..."


kubectl create namespace "$ARGOCD_NAMESPACE" \
    --dry-run=client \
    -o yaml |
kubectl apply -f -


if kubectl get deployment argocd-server \
    -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then

    echo "ArgoCD is already installed."

else

    kubectl apply \
        -n "$ARGOCD_NAMESPACE" \
        --server-side \
        --force-conflicts \
        -f "https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

fi


echo
echo "Waiting for ArgoCD server..."

kubectl wait \
    --for=condition=Available \
    deployment/argocd-server \
    -n "$ARGOCD_NAMESPACE" \
    --timeout=300s


echo
echo "Creating telemetry namespace..."

kubectl apply \
    -f kubernetes/base/namespace.yaml


echo


# ============================================================
# 9. Observability + ArgoCD Application
# ============================================================

echo "[9/10] Installing observability stack..."


# ------------------------------------------------------------
# Prometheus / kube-prometheus-stack
# ------------------------------------------------------------

echo
echo "Adding prometheus-community Helm repository..."

helm repo add prometheus-community \
    https://prometheus-community.github.io/helm-charts

helm repo update


kubectl create namespace "$MONITORING_NAMESPACE" \
    --dry-run=client \
    -o yaml |
kubectl apply -f -


echo
echo "Installing kube-prometheus-stack..."


if helm status monitoring \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "Prometheus stack already installed."

else

    helm install monitoring \
        prometheus-community/kube-prometheus-stack \
        -n "$MONITORING_NAMESPACE" \
        --wait \
        --timeout 10m

fi


echo
echo "Prometheus stack installed."
echo


# ------------------------------------------------------------
# Grafana Helm repository
# ------------------------------------------------------------

echo "Adding Grafana Helm repository..."

helm repo add grafana \
    https://grafana.github.io/helm-charts

helm repo update

echo


# ------------------------------------------------------------
# Loki
# ------------------------------------------------------------

echo "Adding Grafana Community Helm repository..."

helm repo add grafana-community \
    https://grafana-community.github.io/helm-charts

helm repo update


echo
echo "Installing Loki ${LOKI_VERSION}..."


if helm status loki \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "Loki already installed."

else

    helm install loki \
        "$LOKI_CHART" \
        --version "$LOKI_VERSION" \
        -n "$MONITORING_NAMESPACE" \
        -f "$REPO_DIR/observability/loki/values.yaml" \
        --wait \
        --timeout 10m

fi


echo
echo "Loki installed."
echo


# ------------------------------------------------------------
# Promtail
# ------------------------------------------------------------

echo "Installing Promtail..."


if helm status promtail \
    -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then

    echo "Promtail already installed."

else

    helm install promtail \
        grafana/promtail \
        -n "$MONITORING_NAMESPACE" \
        --wait \
        --timeout 10m

fi


echo
echo "Observability stack installation completed."
echo


# ------------------------------------------------------------
# ArgoCD Application
#
# IMPORTANT:
# Prometheus is installed BEFORE the first application sync.
# This guarantees ServiceMonitor CRDs already exist.
# ------------------------------------------------------------

echo "Creating ArgoCD Application..."


kubectl apply \
    -f argocd/application.yaml


echo
echo "Waiting briefly for ArgoCD to register the Application..."

sleep 10


echo
echo "Forcing ArgoCD synchronization..."


kubectl patch application production-cloud-platform \
    -n "$ARGOCD_NAMESPACE" \
    --type merge \
    -p '{"operation":{"sync":{}}}'


echo


# ============================================================
# Platform readiness
# ============================================================

echo
echo "============================================================"
echo " Waiting for platform readiness"
echo "============================================================"

echo
echo "Waiting for ArgoCD Application to become Healthy..."

kubectl wait \
    --for=jsonpath='{.status.health.status}'=Healthy \
    application/production-cloud-platform \
    -n "$ARGOCD_NAMESPACE" \
    --timeout=600s

echo
echo "ArgoCD Application is Healthy."

echo
echo "Waiting for ingestion-api..."

kubectl rollout status deployment/ingestion-api \
    -n "$TELEMETRY_NAMESPACE" \
    --timeout=300s

echo
echo "Waiting for processing-service..."

kubectl rollout status deployment/processing-service \
    -n "$TELEMETRY_NAMESPACE" \
    --timeout=300s

echo
echo "Waiting for postgres-exporter..."

kubectl rollout status deployment/postgres-exporter \
    -n "$TELEMETRY_NAMESPACE" \
    --timeout=300s

echo
echo "Waiting for PostgreSQL..."

kubectl wait \
    --for=condition=Ready \
    pod/postgres-0 \
    -n "$TELEMETRY_NAMESPACE" \
    --timeout=300s

echo
echo "Waiting for simulator..."

kubectl rollout status deployment/simulator \
    -n "$TELEMETRY_NAMESPACE" \
    --timeout=300s

echo
echo "============================================================"
echo " Platform is ready."
echo "============================================================"
echo


# ============================================================
# 10. Disaster Recovery smoke tests
# ============================================================

echo "[10/10] Running Disaster Recovery smoke tests..."


# ============================================================
# Kubernetes
# ============================================================

echo
echo "============================================================"
echo " Kubernetes Nodes"
echo "============================================================"

kubectl get nodes -o wide


echo
echo "============================================================"
echo " All Pods"
echo "============================================================"

kubectl get pods -A


echo
echo "============================================================"
echo " Platform Pods"
echo "============================================================"

kubectl get pods -n "$TELEMETRY_NAMESPACE"


echo
echo "============================================================"
echo " Monitoring Pods"
echo "============================================================"

kubectl get pods -n "$MONITORING_NAMESPACE"

echo


# ============================================================
# ArgoCD Application
# ============================================================

echo "============================================================"
echo " ArgoCD Application"
echo "============================================================"

kubectl get application production-cloud-platform \
    -n "$ARGOCD_NAMESPACE" \
    -o wide

echo


# ============================================================
# Services
# ============================================================

echo "============================================================"
echo " Platform Services"
echo "============================================================"

kubectl get svc -n "$TELEMETRY_NAMESPACE"

echo


# ============================================================
# ServiceMonitors
# ============================================================

echo "============================================================"
echo " ServiceMonitors"
echo "============================================================"

kubectl get servicemonitors -A

echo


# ============================================================
# Helm releases
# ============================================================

echo "============================================================"
echo " Helm Releases"
echo "============================================================"

helm list -A

echo


# ============================================================
# Port-forward helper
# ============================================================

port_forward_and_run() {

    local namespace="$1"
    local resource="$2"
    local local_port="$3"
    local remote_port="$4"

    shift 4

    local log_file
    local pf_pid

    log_file="$(mktemp)"

    kubectl port-forward \
        -n "$namespace" \
        "$resource" \
        "${local_port}:${remote_port}" \
        >"$log_file" 2>&1 &

    pf_pid=$!

    sleep 3

    "$@"

    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" >/dev/null 2>&1 || true

    rm -f "$log_file"
}


# ============================================================
# ingestion-api /metrics
# ============================================================

echo "============================================================"
echo " ingestion-api /metrics"
echo "============================================================"

port_forward_and_run \
    "$TELEMETRY_NAMESPACE" \
    "svc/ingestion-api" \
    8000 \
    8000 \
    bash -c \
    'curl -fsS http://127.0.0.1:8000/metrics | head -20'

echo


# ============================================================
# processing-service /metrics
# ============================================================

echo "============================================================"
echo " processing-service /metrics"
echo "============================================================"

port_forward_and_run \
    "$TELEMETRY_NAMESPACE" \
    "svc/processing-service" \
    8001 \
    8001 \
    bash -c \
    'curl -fsS http://127.0.0.1:8001/metrics | head -20'

echo


# ============================================================
# postgres-exporter /metrics
# ============================================================

echo "============================================================"
echo " postgres-exporter /metrics"
echo "============================================================"

port_forward_and_run \
    "$TELEMETRY_NAMESPACE" \
    "svc/postgres-exporter" \
    9187 \
    9187 \
    bash -c \
    'curl -fsS http://127.0.0.1:9187/metrics | grep "^pg_up" || true'

echo


# ============================================================
# Prometheus API
# ============================================================

echo "============================================================"
echo " Prometheus API / Targets"
echo "============================================================"

port_forward_and_run \
    "$MONITORING_NAMESPACE" \
    "svc/monitoring-kube-prometheus-prometheus" \
    9090 \
    9090 \
    bash -c \
    '
    curl -fsS \
      http://127.0.0.1:9090/api/v1/targets |
      jq -r "
        .data.activeTargets[]
        | [
            .labels.job,
            .health,
            .scrapeUrl
          ]
        | @tsv
      "
    '

echo


# ============================================================
# Loki labels
# ============================================================

echo "============================================================"
echo " Loki labels"
echo "============================================================"

port_forward_and_run \
    "$MONITORING_NAMESPACE" \
    "svc/loki-gateway" \
    3100 \
    80 \
    bash -c \
    '
    curl -fsS \
      -G \
      http://127.0.0.1:3100/loki/api/v1/labels |
      jq
    '

echo


# ============================================================
# Loki processing-service logs
# ============================================================

echo "============================================================"
echo " Loki -> processing-service logs"
echo "============================================================"

port_forward_and_run \
    "$MONITORING_NAMESPACE" \
    "svc/loki-gateway" \
    3100 \
    80 \
    bash -c \
    '
    curl -fsS \
      -G \
      --data-urlencode "query={namespace=\"telemetry-system\",container=\"processing-service\"}" \
      --data-urlencode "limit=20" \
      http://127.0.0.1:3100/loki/api/v1/query_range |
      jq "
        {
          status: .status,
          streams: (
            .data.result
            | map({
                labels: .stream,
                entries: (.values | length)
              })
          )
        }
      "
    '

echo


# ============================================================
# Recent processing-service logs
# ============================================================

echo "============================================================"
echo " Recent processing-service logs"
echo "============================================================"

kubectl logs \
    -n "$TELEMETRY_NAMESPACE" \
    deployment/processing-service \
    --tail=10

echo


# ============================================================
# Final summary
# ============================================================

echo "============================================================"
echo " Disaster Recovery Bootstrap Completed"
echo "============================================================"

echo
echo "Installed components:"
echo
echo "  Docker"
echo "  kubectl ${K8S_MINOR_VERSION}"
echo "  Kind ${KIND_VERSION}"
echo "  Helm"
echo "  ArgoCD"
echo "  Production Cloud Platform"
echo "  kube-prometheus-stack"
echo "  Loki ${LOKI_VERSION}"
echo "  Promtail"
echo

echo "Final platform state:"
kubectl get pods -n "$TELEMETRY_NAMESPACE"

echo
echo "Final observability state:"
kubectl get pods -n "$MONITORING_NAMESPACE"

echo
echo "============================================================"
echo " DR smoke tests completed."
echo "============================================================"
echo
