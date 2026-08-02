Installed as part of kube-prometheus-stack.

```bash

helm repo add prometheus-community \
https://prometheus-community.github.io/helm-charts

helm repo update

kubectl create namespace monitoring

helm install monitoring \
prometheus-community/kube-prometheus-stack \
-n monitoring

kubectl get pods -n monitoring
kubectl get svc -n monitoring

```

Prometheus datasource is configured automatically.

Loki datasource will be added during observability expansion.
