Helm values for Loki deployment.

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm search repo grafana/loki

helm show values grafana/loki \
> observability/loki/values.yaml
```
