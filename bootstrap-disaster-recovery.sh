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

TEMP_CREDENTIAL_DIR=""

cleanup_temp_credentials() {
    if [[ -n "${TEMP_CREDENTIAL_DIR:-}" &&
          -d "$TEMP_CREDENTIAL_DIR" ]]; then
        rm -rf -- "$TEMP_CREDENTIAL_DIR"
    fi

    TEMP_CREDENTIAL_DIR=""
}

trap cleanup_temp_credentials EXIT

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
# Prepare External Secrets source credentials
# ============================================================

prepare_source_secrets() {
    local secret_namespace="secret-source"

    echo "Preparing External Secrets source credentials..."

    kubectl create namespace "$secret_namespace" \
        --dry-run=client -o yaml |
        kubectl apply -f -

    TEMP_CREDENTIAL_DIR="$(mktemp -d)"
    chmod 700 "$TEMP_CREDENTIAL_DIR"

    if ! kubectl get secret telemetry-credentials \
        -n "$secret_namespace" >/dev/null 2>&1; then

        printf '%s' 'telemetry' > "$TEMP_CREDENTIAL_DIR/POSTGRES_USER"
        openssl rand -hex 32 > "$TEMP_CREDENTIAL_DIR/POSTGRES_PASSWORD"
        chmod 600 "$TEMP_CREDENTIAL_DIR/POSTGRES_USER" \
            "$TEMP_CREDENTIAL_DIR/POSTGRES_PASSWORD"

        kubectl create secret generic telemetry-credentials \
            -n "$secret_namespace" \
            --from-file=POSTGRES_USER="$TEMP_CREDENTIAL_DIR/POSTGRES_USER" \
            --from-file=POSTGRES_PASSWORD="$TEMP_CREDENTIAL_DIR/POSTGRES_PASSWORD"

        echo "Created PostgreSQL source credentials."
    else
        kubectl get secret telemetry-credentials \
            -n "$secret_namespace" \
            -o json |
            jq -e '
                .data
                | has("POSTGRES_USER")
                  and has("POSTGRES_PASSWORD")
                  and (.POSTGRES_USER | @base64d | length > 0)
                  and (.POSTGRES_PASSWORD | @base64d | length > 0)
            ' >/dev/null || {
                echo "ERROR: Existing telemetry-credentials Secret has missing or empty required values." >&2
                return 1
            }

        echo "PostgreSQL source Secret exists and has required keys."
    fi

    if ! kubectl get secret rabbitmq-credentials \
        -n "$secret_namespace" >/dev/null 2>&1; then

        printf '%s' 'telemetry' > "$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_USER"
        openssl rand -hex 32 > "$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_PASS"

        cp "$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_USER" \
            "$TEMP_CREDENTIAL_DIR/RABBITMQ_USER"
        cp "$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_PASS" \
            "$TEMP_CREDENTIAL_DIR/RABBITMQ_PASSWORD"

        chmod 600 "$TEMP_CREDENTIAL_DIR"/RABBITMQ_*

        kubectl create secret generic rabbitmq-credentials \
            -n "$secret_namespace" \
            --from-file=RABBITMQ_DEFAULT_USER="$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_USER" \
            --from-file=RABBITMQ_DEFAULT_PASS="$TEMP_CREDENTIAL_DIR/RABBITMQ_DEFAULT_PASS" \
            --from-file=RABBITMQ_USER="$TEMP_CREDENTIAL_DIR/RABBITMQ_USER" \
            --from-file=RABBITMQ_PASSWORD="$TEMP_CREDENTIAL_DIR/RABBITMQ_PASSWORD"

        echo "Created RabbitMQ source credentials."
    else
        kubectl get secret rabbitmq-credentials \
            -n "$secret_namespace" \
            -o json |
            jq -e '
                .data
                | has("RABBITMQ_DEFAULT_USER")
                  and has("RABBITMQ_DEFAULT_PASS")
                  and has("RABBITMQ_USER")
                  and has("RABBITMQ_PASSWORD")
                  and (.RABBITMQ_DEFAULT_USER | @base64d | length > 0)
                  and (.RABBITMQ_DEFAULT_PASS | @base64d | length > 0)
                  and (.RABBITMQ_USER | @base64d | length > 0)
                  and (.RABBITMQ_PASSWORD | @base64d | length > 0)
            ' >/dev/null || {
                echo "ERROR: Existing rabbitmq-credentials Secret has missing or empty required values." >&2
                return 1
            }

        echo "RabbitMQ source Secret exists and has required keys."
    fi
    cleanup_temp_credentials
}

# ============================================================
# Prepare ESO resources before the first ArgoCD sync
# ============================================================

prepare_eso_resources() {
    echo "Applying ESO resources from the Helm chart..."

    helm template production-cloud-platform \
        ./helm/production-cloud-platform \
        --namespace "$TELEMETRY_NAMESPACE" \
        --show-only templates/eso-rbac.yaml |
        kubectl apply -f -

    helm template production-cloud-platform \
        ./helm/production-cloud-platform \
        --namespace "$TELEMETRY_NAMESPACE" \
        --show-only templates/secret-store.yaml |
        kubectl apply -f -

    kubectl wait \
        --for=condition=Ready \
        secretstores.external-secrets.io/kubernetes-source \
        -n "$TELEMETRY_NAMESPACE" \
        --timeout=120s

    helm template production-cloud-platform \
        ./helm/production-cloud-platform \
        --namespace "$TELEMETRY_NAMESPACE" \
        --show-only templates/external-secrets.yaml |
        kubectl apply -f -

    echo "Waiting for PostgreSQL ExternalSecret..."
    kubectl wait \
        --for=condition=Ready \
        externalsecrets.external-secrets.io/telemetry-credentials \
        -n "$TELEMETRY_NAMESPACE" \
        --timeout=180s

    echo "Waiting for RabbitMQ ExternalSecret..."
    kubectl wait \
        --for=condition=Ready \
        externalsecrets.external-secrets.io/rabbitmq-credentials \
        -n "$TELEMETRY_NAMESPACE" \
        --timeout=180s

    kubectl get secret telemetry-secret-eso \
        -n "$TELEMETRY_NAMESPACE" -o json |
        jq -e '.data | has("POSTGRES_USER") and has("POSTGRES_PASSWORD")' \
        >/dev/null

    kubectl get secret rabbitmq-secret-eso \
        -n "$TELEMETRY_NAMESPACE" -o json |
        jq -e '.data | has("RABBITMQ_DEFAULT_USER") and has("RABBITMQ_DEFAULT_PASS") and has("RABBITMQ_USER") and has("RABBITMQ_PASSWORD")' \
        >/dev/null

    echo "ESO is ready; both target Secrets contain the required keys."
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
    openssl \
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
# Metrics Server for HPA
# ============================================================

echo "Installing metrics-server for HPA..."

kubectl apply -f \
    https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml

if ! kubectl get deployment metrics-server \
    -n kube-system -o json |
    jq -e '[.spec.template.spec.containers[].args[]?] |
        index("--kubelet-insecure-tls") != null' >/dev/null; then

    kubectl patch deployment metrics-server \
        -n kube-system \
        --type='json' \
        -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi

kubectl rollout status deployment/metrics-server \
    -n kube-system \
    --timeout=180s

echo "metrics-server deployment is ready."


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
echo "Preparing External Secrets source credentials..."

prepare_source_secrets


echo


# ============================================================
# 9. Observability + ArgoCD Application
# ============================================================

echo "[9/10] Installing observability stack..."


# ------------------------------------------------------------
# External Secrets Operator
# ------------------------------------------------------------

echo
echo "Installing External Secrets Operator..."

helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
    --version 2.12.0 \
    --namespace external-secrets \
    --create-namespace \
    --wait \
    --timeout 5m

kubectl wait \
    --for=condition=Established \
    crd/secretstores.external-secrets.io \
    --timeout=120s

kubectl wait \
    --for=condition=Established \
    crd/externalsecrets.external-secrets.io \
    --timeout=120s

kubectl wait \
    --for=condition=Available \
    deployment/external-secrets \
    -n external-secrets \
    --timeout=180s

prepare_eso_resources


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
echo "Installing/upgrading kube-prometheus-stack..."


helm upgrade --install monitoring \
    prometheus-community/kube-prometheus-stack \
    --version 90.0.0 \
    -n "$MONITORING_NAMESPACE" \
    -f observability/alertmanager/values.yaml \
    --wait \
    --timeout 10m


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
    https://grafana-community.github.io/helm-charts \
    --force-update

helm repo update


echo
echo "Installing/upgrading Loki ${LOKI_VERSION}..."


helm upgrade --install loki \
    "$LOKI_CHART" \
    --version "$LOKI_VERSION" \
    -n "$MONITORING_NAMESPACE" \
    -f "$REPO_DIR/observability/loki/values.yaml" \
    -f "$REPO_DIR/recovery/minio/loki-minio-values.yaml" \
    --wait \
    --timeout 10m


echo
echo "Loki installation/upgrade completed."
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
echo "Verifying Alembic migration and database index..."

migration_ready=false

for attempt in $(seq 1 30); do
    if migration_check="$(
        kubectl exec postgres-0 \
            -n "$TELEMETRY_NAMESPACE" \
            -- sh -c \
            "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Atq -c \"SELECT (SELECT version_num = '0002' FROM alembic_version LIMIT 1) AND to_regclass('public.ix_measurements_bridge_id_timestamp') IS NOT NULL;\"" \
            2>/dev/null
    )" && [ "$migration_check" = "t" ]; then
        migration_ready=true
        break
    fi

    echo "Migration or index not verified yet (attempt $attempt/30)."
    sleep 10
done

if [ "$migration_ready" != true ]; then
    echo "ERROR: Alembic revision 0002 or its index was not verified." >&2
    exit 1
fi

echo "Alembic revision 0002 and database index verified."
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


# ============================================================
# Metrics Server and HPA
# ============================================================

echo
echo "============================================================"
echo " Metrics Server"
echo "============================================================"

metrics_ready=false

for attempt in $(seq 1 12); do
    if kubectl top nodes >/dev/null 2>&1 &&
       kubectl top pods -n "$TELEMETRY_NAMESPACE" >/dev/null 2>&1; then
        metrics_ready=true
        break
    fi

    echo "Node or Pod metrics not ready yet (attempt $attempt/12)."
    sleep 10
done

if [ "$metrics_ready" != true ]; then
    echo "ERROR: Metrics API did not become available." >&2
    exit 1
fi

echo
echo "Pod resource metrics:"
kubectl top pods -n "$TELEMETRY_NAMESPACE"

echo
echo "============================================================"
echo " Processing Service HPA"
echo "============================================================"

kubectl get hpa processing-service \
    -n "$TELEMETRY_NAMESPACE" -o wide

kubectl get hpa processing-service \
    -n "$TELEMETRY_NAMESPACE" -o json |
    jq -e '
        .spec.scaleTargetRef.name == "processing-service"
        and .spec.metrics[0].resource.name == "cpu"
        and .spec.metrics[0].resource.target.averageUtilization == 50
        and .spec.minReplicas == 1
        and .spec.maxReplicas == 3
    ' >/dev/null

echo "HPA configuration validated."


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
    local rc=0

    log_file="$(mktemp)"

    kubectl port-forward \
        -n "$namespace" \
        "$resource" \
        "${local_port}:${remote_port}" \
        >"$log_file" 2>&1 &
    pf_pid=$!

    # Wait briefly for the port-forward to initialize.
    sleep 3

    if ! kill -0 "$pf_pid" 2>/dev/null; then
        echo "ERROR: kubectl port-forward exited unexpectedly." >&2
        cat "$log_file" >&2
        rc=1
    else
        "$@" || rc=$?
    fi

    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" >/dev/null 2>&1 || true

    if [[ "$rc" -ne 0 && -s "$log_file" ]]; then
        cat "$log_file" >&2
    fi

    rm -f -- "$log_file"
    return "$rc"
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
    bash -c '
        metrics="$(curl -fsS --connect-timeout 5 --max-time 10 \
            http://127.0.0.1:9187/metrics)"

        printf "%s\n" "$metrics" |
            grep -Eq "^pg_up(\{[^}]*\})?[[:space:]]+1([.]0*)?$" || {
                echo "ERROR: PostgreSQL exporter does not report pg_up 1." >&2
                exit 1
            }

        printf "%s\n" "$metrics" | grep -E "^pg_up(\{|[[:space:]])"
    '
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
# Alert webhook receiver health check
# ============================================================

echo
echo "============================================================"
echo " Alert webhook receiver health"
echo "============================================================"

kubectl rollout status deployment/alert-webhook-receiver \
    -n "$MONITORING_NAMESPACE" \
    --timeout=120s

port_forward_and_run \
    "$MONITORING_NAMESPACE" \
    "svc/alert-webhook-receiver" \
    18080 \
    8080 \
    bash -c '
        HTTP_CODE="$(curl -sS -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 \
            --max-time 10 \
            http://127.0.0.1:18080/health)" || {
                echo "ERROR: Webhook receiver health request failed." >&2
                exit 1
            }

        if [[ "$HTTP_CODE" != "200" ]]; then
            echo "ERROR: Webhook receiver returned HTTP $HTTP_CODE; expected 200." >&2
            exit 1
        fi

        echo "Webhook receiver health check passed: HTTP 200."
    '

# ============================================================
# Additional checks for recently added layers
# ============================================================

echo
echo "============================================================"
echo " RabbitMQ"
echo "============================================================"

RABBITMQ_POD="$(
    kubectl get pods -n "$TELEMETRY_NAMESPACE" -o json |
        jq -r '
            .items[]
            | select(.status.phase == "Running")
            | select(any(.spec.containers[]?; .image | contains("rabbitmq")))
            | .metadata.name
        ' |
        head -n 1
)"

if [[ -z "$RABBITMQ_POD" ]]; then
    echo "ERROR: Running RabbitMQ pod not found." >&2
    exit 1
fi

kubectl exec -n "$TELEMETRY_NAMESPACE" "$RABBITMQ_POD" -- \
    rabbitmq-diagnostics -q ping

kubectl exec -n "$TELEMETRY_NAMESPACE" "$RABBITMQ_POD" -- \
    rabbitmqctl list_exchanges name |
    grep -Fxq "telemetry"

kubectl exec -n "$TELEMETRY_NAMESPACE" "$RABBITMQ_POD" -- \
    rabbitmqctl list_queues name |
    grep -Fxq "telemetry.measurements"

echo "RabbitMQ broker, exchange and queue verified."

echo
echo "============================================================"
echo " NetworkPolicy"
echo "============================================================"

kubectl get networkpolicy -n "$TELEMETRY_NAMESPACE"

kubectl get networkpolicy -n "$TELEMETRY_NAMESPACE" \
    -o json |
    jq -e '
        any(
            .items[];
            .metadata.name == "telemetry-ingress-default-deny"
        )
    ' >/dev/null

echo "NetworkPolicy default-deny policy verified."

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
