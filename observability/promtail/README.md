Helm values for Promtail deployment.

```bash
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm search repo grafana/promtail

helm show values grafana/promtail \
> observability/promtail/values.yaml
```
