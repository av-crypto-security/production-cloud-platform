Promtail collects container logs from Kubernetes nodes and forwards them to Loki.

In this project Promtail is deployed as a separate Helm release and sends logs to the official Grafana Loki Helm chart running in Monolithic mode.

For local development Loki uses embedded MiniIO (S3-compatible object storage).

Future versions of the project may migrate from Promtail to Grafana Alloy as the recommended log collection agent.
