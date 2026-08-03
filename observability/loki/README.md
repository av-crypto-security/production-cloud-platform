Helm values for Loki deployment.
Local development uses the official grafana/loki-stack Helm chart.
Only Loki and Promtail are enabled.
Grafana and Prometheus are provided by kube-prometheus-stack.

For production (Terraform/AWS), the project will migrate to the modern grafana/loki chart with object storage.

