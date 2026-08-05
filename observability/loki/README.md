Local development uses the official Grafana Loki Helm chart in Monolithic deployment mode with filesystem storage.

This configuration is intended for local Kubernetes clusters (Kind).

Production deployment will use the distributed Loki architecture with object storage (Amazon S3) provisioned by Terraform.
