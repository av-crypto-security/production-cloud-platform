Grafana Loki is deployed using official Helm chart in Monilithic mode.

For local Kubernetes development the deployment uses embedded MiniIO as S3-compatible object storage.

Production deployment is planned to use external object storage (Amazon S3 or compatible) provisioned with Terraform.
