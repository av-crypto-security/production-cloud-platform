# Production Cloud Platform

Production-style platform engineering project demonstrating a complete
software delivery and GitOps lifecycle:

```text
Docker → Kubernetes → GHCR → Helm → GitHub Actions → ArgoCD
```

The platform simulates telemetry ingestion and processing for
infrastructure monitoring systems and demonstrates containerization,
Kubernetes orchestration, CI/CD automation, GitOps delivery,
observability, asynchronous messaging, alerting and disaster recovery.


## GitOps Workflow

```text
Git Commit
    ↓
Git Push
    ↓
GitHub
    ↓
GitHub Actions
    ↓
GitHub Container Registry (GHCR)
    ↓
ArgoCD
    ↓
Helm
    ↓
Kubernetes
```

ArgoCD continuously reconciles the Kubernetes cluster with the desired
state stored in Git.
Automated synchronization and self-healing reconciliation are enabled.


## Current Architecture

The current implemented telemetry pipeline is:

```text
┌─────────────────────┐
│  Sensor Simulator   │
└──────────┬──────────┘
           │ HTTP / JSON
           ▼
┌─────────────────────┐
│   Ingestion API     │
│      FastAPI        │
└──────────┬──────────┘
           │ AMQP
           ▼
┌──────────────────────────────┐
│           RabbitMQ           │
│                              │
│  telemetry exchange          │
│          │                   │
│          ▼                   │
│  telemetry.measurements      │
│          │                   │
│          ├── retry / TTL ────┤
│          │                   │
│          └── DLX → DLQ       │
└──────────┬───────────────────┘
           │ AMQP
           ▼
┌─────────────────────┐
│ Processing Worker   │
│ manual ACK          │
└──────────┬──────────┘
           │ SQL transaction
           ▼
┌─────────────────────┐
│     PostgreSQL      │
│ measurements        │
│ alerts              │
└─────────────────────┘
```

The platform uses RabbitMQ as a durable asynchronous buffer between the
Ingestion API and Processing Worker.


## Messaging and Reliability

RabbitMQ provides asynchronous delivery and failure handling between
the application services.

Implemented reliability mechanisms include:

- durable direct exchange
- durable queues
- persistent messages
- publisher confirms
- mandatory message publishing
- manual message acknowledgements
- prefetch_count=1
- PostgreSQL transaction before RabbitMQ ACK
- bounded retry queue
- 10-second retry TTL
- maximum 3 retries
- dead-letter exchange
- dead-letter queue
- queue and broker metrics exposed to Prometheus

### Queue topology

```text
telemetry exchange
       │
       ├── measurement
       ▼
telemetry.measurements
       │
       │ processing failure
       ▼
telemetry.measurements.retry
       │
       │ TTL = 10 seconds
       │
       └──────────────→ telemetry exchange
                              │
                              ▼
                       telemetry.measurements
       
After maximum retries:

telemetry.dlx
       │
       ▼
telemetry.measurements.dlq
```

The retry mechanism performs up to three retries after the initial
processing attempt.
The platform uses at-least-once delivery semantics, not exactly-once
processing.
If a worker fails after a successful PostgreSQL transaction but before
the RabbitMQ acknowledgement, RabbitMQ may redeliver the message.
Full idempotent event processing is intentionally deferred to the
database migration layer.

### Failure validation

The RabbitMQ failure path has been validated using an intentionally
malformed message.

The demonstrated flow is:

```text
Invalid message
      ↓
Processing failure
      ↓
Retry queue
      ↓
TTL expiration
      ↓
Main queue
      ↓
Bounded retries
      ↓
Dead-letter queue
```

The DLQ was verified to receive the failed message and was subsequently
purged to restore a clean operational state.


## Observability

The platform implements application, infrastructure and database
observability using Prometheus, Grafana, Loki and Alertmanager.

### Metrics

```text
Application metrics ───────┐
RabbitMQ metrics ──────────┤
PostgreSQL exporter ───────┤
                           ▼
                       Prometheus
                           │
                           ▼
                        Grafana
```

Implemented components:

- Prometheus
- ServiceMonitor
- PostgreSQL Exporter
- RabbitMQ metrics
- Grafana dashboards
- application metrics

### Logging

```text
Kubernetes workloads
        │
        ▼
     Promtail
        │
        ▼
       Loki
        │
        ▼
     Grafana
```

Promtail collects container logs and forwards them to Loki for
centralized querying and visualization.

### Alerting

Alerting is implemented using Prometheus and Alertmanager.
Prometheus evaluates custom `PrometheusRule` resources for platform
health conditions. Alerts are routed through Alertmanager using an
`AlertmanagerConfig` resource.

The platform webhook route is selected by the
`category=platform` matcher and delivers notifications to an in-cluster
HTTP webhook receiver.

The demonstrated notification lifecycle is:

```text
INACTIVE → PENDING → FIRING → RESOLVED
```

The end-to-end delivery flow is:

```text
Kubernetes workload
        │
        ▼
    Prometheus
        │
        ▼
 PrometheusRule
        │
        ▼
   Alertmanager
        │
        ▼
AlertmanagerConfig
        │
        ▼
HTTP webhook receiver
        │
        ▼
   Container logs
```

The webhook receiver is implemented as a small Flask application
running behind Gunicorn.
The receiver logs notification events including:
- alert status
- alert name
- severity
- namespace
The demonstrated controlled incident uses a temporary Kubernetes
Deployment with a failing readiness probe to trigger
`PlatformPodNotReady`.
Alertmanager is configured to send both firing and resolved
notifications to the webhook receiver.


## Disaster Recovery

The repository includes a tested disaster-recovery bootstrap script:

```bash
./bootstrap-disaster-recovery.sh
```

For a clean recovery, the script is recommended to be placed outside
the repository, for example:

```bash
$HOME/bootstrap-disaster-recovery.sh
```

The script clones the repository into:

```bash
$HOME/production-cloud-platform/
```

This keeps the bootstrap script outside the repository during a
from-scratch recovery.

The recovery process provisions:

```text
Docker
   ↓
kubectl
   ↓
Kind
   ↓
Helm
   ↓
ArgoCD
   ↓
Prometheus / Grafana
   ↓
Loki / Promtail
   ↓
Production Cloud Platform
```

After deployment, the script waits for the platform workloads to become
ready and runs automated smoke tests covering Kubernetes, ArgoCD,
application metrics, PostgreSQL Exporter, Prometheus targets and Loki.


## Container Registry

Container images are published to GitHub Container Registry (GHCR).
Current application images:

```
ghcr.io/av-crypto-security/ingestion-api:v1.3.0
ghcr.io/av-crypto-security/processing-service:v1.3.0
ghcr.io/av-crypto-security/simulator:v1.0.0
ghcr.io/av-crypto-security/alert-webhook-receiver:v1.0.1
```

Versioned container images are referenced by the Kubernetes/Helm
deployment configuration.


## Helm

The Kubernetes manifests are packaged as a reusable Helm chart.

Current Helm features include:
- configurable image repositories and tags
- configurable replica counts
- parameterized ConfigMaps
- parameterized Secrets
- namespace abstraction using `.Release.Namespace`
- Kubernetes resource templating
- application and infrastructure configuration separation

The same chart structure can be reused across Kubernetes environments
with environment-specific values.


## CI/CD Pipeline

The CI/CD workflow is implemented using GitHub Actions and GHCR.
```text
Developer
    │
    ▼
Git Push
    │
    ▼
GitHub Repository
    │
    ▼
GitHub Actions
    │
    ├── Build
    ├── Validate
    └── Push
          │
          ▼
        GHCR
          │
          ▼
       ArgoCD
          │
          ▼
        Helm
          │
          ▼
     Kubernetes
```

ArgoCD performs automated synchronization and self-healing
reconciliation of the deployed application.


## Kubernetes Platform

The platform currently runs on Kubernetes using Kind for the local
production-style environment.

Implemented Kubernetes capabilities include:

- Deployments
- StatefulSets
- Services
- ConfigMaps
- Secrets
- PersistentVolumeClaims
- health checks
- rolling updates
- self-healing workloads
- declarative resource management
- Helm-based deployment
- ArgoCD reconciliation


## Current Implementation Status

### Implemented

- Sensor Simulator service
- FastAPI Ingestion API
- PostgreSQL persistence
- Telemetry Processing Worker
- Docker containerization
- Docker Compose development deployment
- Kubernetes deployment using Kind
- ConfigMaps and Secrets
- Stateful PostgreSQL storage
- GitHub Container Registry integration
- Helm chart
- GitHub Actions CI pipeline
- ArgoCD GitOps
- automated synchronization
- self-healing reconciliation
- Prometheus monitoring
- ServiceMonitor integration
- PostgreSQL Exporter
- RabbitMQ metrics
- Grafana dashboards
- Loki centralized logging
- Promtail log collection
- Alertmanager
- PrometheusRule alerts
- AlertmanagerConfig webhook routing
- end-to-end firing/resolved notification validation
- RabbitMQ durable messaging
- RabbitMQ retry handling
- RabbitMQ dead-letter queue
- RabbitMQ failure-path validation
- disaster-recovery bootstrap script
- automated recovery smoke tests


### Next engineering layers

The remaining platform layers are intentionally kept limited and
focused:

- Alembic database migrations
- HPA
- NetworkPolicy
- External Secrets Operator
- final platform validation and documentation

Terraform infrastructure is maintained as a separate
cloud-infrastructure track and is not a dependency for the current
platform freeze.


## Platform Workflow

1. Sensor Simulator generates telemetry events.
2. The Ingestion API validates incoming telemetry.
3. The API publishes telemetry to RabbitMQ using AMQP.
4. RabbitMQ provides durable asynchronous buffering.
5. The Processing Worker consumes messages using manual acknowledgements.
6. Processing results and alert metadata are stored in PostgreSQL.
7. Prometheus collects application, RabbitMQ and database metrics.
8. Grafana visualizes platform metrics and logs.
9. Alertmanager routes platform alerts to the webhook receiver.
10. ArgoCD continuously reconciles the Kubernetes deployment with Git.


## Security Notice

This repository contains demonstration credentials intended only for
local testing and portfolio demonstration.

Kubernetes Secrets and Helm values must not be treated as production
secret management.

Production deployments should use properly managed secret delivery,
such as External Secrets Operator or another dedicated secret
management solution.


## Screenshots

Architecture, deployment, observability and RabbitMQ evidence are
available in:

```
screenshots/
```


## Technology Stack

### Application

- Python
- FastAPI
- Flask
- Gunicorn
- PostgreSQL
- Pika / AMQP

### Containers and Kubernetes

- Docker
- Kubernetes
- Kind
- Helm

### CI/CD and GitOps

- GitHub Actions
- GitHub Container Registry
- ArgoCD
- GitOps

### Observability

- Prometheus
- ServiceMonitor
- PostgreSQL Exporter
- Grafana
- Loki
- Promtail
- Alertmanager
- PrometheusRule
- AlertmanagerConfig

### Messaging

- RabbitMQ


## License

MIT License

