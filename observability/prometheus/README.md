Installed via kube-prometheus-stack.

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

Current configuration uses default Helm values.

Custom values will be introduced during Terraform/GitOps migration.
