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
The current implementation provides at-least-once delivery semantics,
but does not guarantee exactly-once processing or full application-level idempotency.
Database constraints and an explicit idempotency strategy would be
separate future enhancements.

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


## Database Migrations

Database schema lifecycle is managed by **Alembic**.
The current migration flow is:

```text
Argo CD Sync
     |
     v
PostgreSQL
     |
     v
Alembic migration Job
     |
     v
alembic upgrade head
     |
     v
Application workloads
```

The migration environment is stored in:

```text
services/processing-service/alembic/
```

The processing-service image contains the Alembic environment and is reused
by the Kubernetes migration Job.

### Migration Strategy

The project adopted Alembic against an existing PostgreSQL database
without recreating the database or deleting the existing persistent volume.
The migration history is:

```text
0001  baseline existing schema
  |
  v
0002  add measurements lookup index
```

Revision `0001` describes the existing production schema and is used
as the baseline for Alembic version tracking.
Revision `0002` introduces the first real schema change:

```text
measurements
    |
    +-- (bridge_id, timestamp)
          |
          v
    ix_measurements_bridge_id_timestamp
```

The index is created using PostgreSQL `CREATE INDEX CONCURRENTLY`,
allowing normal table writes to continue during index creation.

### Kubernetes Integration

Database migrations are executed by a dedicated Kubernetes Job:

```text
PostgreSQL StatefulSet
        |
        | sync-wave -1
        v
PostgreSQL ready
        |
        | sync-wave 0
        v
Alembic migration Job
        |
        | sync-wave 1
        v
Application workloads
```

The migration Job is managed by Argo CD as a `Sync` hook and uses:

```yaml
argocd.argoproj.io/hook: Sync
argocd.argoproj.io/hook-delete-policy: BeforeHookCreation,HookSucceeded
```

Successful migration Jobs are therefore removed after completion while
the migration state remains recorded in PostgreSQL through `alembic_version`.
The application containers do not execute database migrations during startup.

### Migration Verification

The deployed migration was verified against the live PostgreSQL database:

```text
Argo CD:
Synced / Healthy / Succeeded

Alembic:
0002

PostgreSQL:
ix_measurements_bridge_id_timestamp
```

The existing application data was preserved during the migration.

### Database Ownership

Alembic is now the authoritative mechanism for database schema lifecycle.
The previous PostgreSQL bootstrap script:

```text
services/postgres/init.sql
```

is retained as a historical artifact from the pre-Alembic architecture.
It is no longer mounted or executed by the current PostgreSQL deployment.
The current schema lifecycle is therefore:

```text
Git
 |
 +-- Alembic revisions
        |
        v
   Argo CD Sync
        |
        v
   Migration Job
        |
        v
   PostgreSQL
```


### Legacy and Historical Artifacts

Some repository files are retained for historical and reference purposes
and are not part of the current deployment path.

* `services/postgres/init.sql` is a legacy database bootstrap script
from the pre-Alembic architecture.
It is no longer mounted or executed by the current PostgreSQL deployment.
Database schema lifecycle is now managed by Alembic migrations.
* `kubernetes/base/` contains the original Kubernetes manifests used
during the early/manual deployment stage of the project.
The current GitOps deployment source of truth is `helm/production-cloud-platform/`
and its manifests are deployed through Argo CD.

These artifacts are intentionally retained to preserve the project's evolution
and deployment history.


## Horizontal Pod Autoscaling

The Processing Worker is configured with a Kubernetes HorizontalPodAutoscaler (HPA)
using CPU utilization as its scaling metric.

### Configuration

* Target: 50% average CPU utilization relative to the container CPU request
* Minimum replicas: 1
* Maximum replicas: 3
* CPU request: 100m
* CPU limit: 500m
* Metrics provider: Kubernetes Metrics Server

Helm renders the HPA when autoscaling is enabled and omits
the Deployment's explicit `spec.replicas` field.
Argo CD is configured to ignore differences in that field
for the `processing-service` Deployment, allowing the HPA controller
to manage replica count without GitOps reconciliation fighting the autoscaler.

### Validation

A controlled CPU-load test was used to validate scaling behavior.

* **Scale-up:** the HPA increased the desired replica count from 1 to 3
when CPU utilization exceeded the configured target.
* **Scale-down:** after the load was removed, the HPA reduced the replica count
from 3 to 2 and then back to 1.
* **Recovery:** the Processing Worker returned to 1/1 Ready,
and Argo CD remained Synced and Healthy.

The test validates Kubernetes CPU-based scaling behavior.
It is not a benchmark of end-to-end message-processing throughput.


## External Secrets Operator

External Secrets Operator (ESO) manages the synchronization
of application credentials from Kubernetes Secrets provisioned outside
the Git repository.

### Architecture

The credential delivery flow is:

```text
Out-of-band credential provisioning
                |
                v
 Kubernetes Secrets
 namespace: secret-source
                |
                v
 SecretStore: kubernetes-source
                |
                v
 ExternalSecret resources
                |
                v
 ESO-managed target Secrets
 namespace: telemetry-system
                |
                v
 Application workloads
```

### Implementation

The current Helm chart defines:

- `SecretStore/kubernetes-source` using the Kubernetes provider.
- `ExternalSecret/telemetry-credentials`, synchronized to `telemetry-secret-eso`.
- `ExternalSecret/rabbitmq-credentials`, synchronized to `rabbitmq-secret-eso`.
- A dedicated ServiceAccount, `eso-kubernetes-reader`, for source access.
- A Role and RoleBinding scoped to the `secret-source` namespace
for reading source Secrets.

The source Secrets are provisioned outside Git and are not generated
by the active Helm chart. Their values must not be committed to the repository.
The source credentials are synchronized into target Secrets in `telemetry-system`.
Application workloads reference these ESO-managed Secrets
through Kubernetes `secretKeyRef` entries.
The existing application environment variable names remain unchanged.
Only the referenced Kubernetes Secret names have changed.

### Validation

The integration was validated against the running Kind cluster:

- Argo CD reported `Synced` and `Healthy`.
- `SecretStore/kubernetes-source` reported `Ready=True`.
- Both ExternalSecrets reported `SecretSynced` and `Ready=True`.
- The target Secrets contained the expected keys.
- Source and target credential values were compared without printing the values;
all six key comparisons matched.
- The application Deployments and PostgreSQL/RabbitMQ StatefulSets were Ready
after the switch.
- PostgreSQL measurement count increased from 27,948 to 27,951
during runtime validation.

### Security Scope

Source Secret access is restricted through Kubernetes RBAC
to the dedicated `eso-kubernetes-reader` ServiceAccount
and the `secret-source` namespace.
The Role grants `get`, `list` and `watch` permissions over Secrets
in that namespace.
It is namespace-scoped, not restricted to individual Secret names.
A dedicated NetworkPolicy for `secret-source` is not currently implemented.
Network isolation and broader cluster access controls remain
separate security considerations.
The ESO integration improves credential delivery and removes
the active chart's direct generation of application Secrets from Helm values.
It does not, by itself, make the local cluster a production-hardened environment.


## Network Policies

The platform uses Kubernetes NetworkPolicies to control ingress traffic
to application and infrastructure Pods in the `telemetry-system` namespace.

### Implemented Policies

The Helm chart defines six NetworkPolicy resources:

- `telemetry-ingress-default-deny` — denies ingress traffic by default
for the selected application and infrastructure Pods.
- `ingestion-api-ingress` — allows traffic from the Sensor Simulator and Prometheus.
- `processing-service-ingress` — allows Prometheus to scrape
the Processing Worker metrics endpoint.
- `postgres-ingress` — allows PostgreSQL connections from the Processing Worker,
PostgreSQL Exporter and Alembic migration Job.
- `rabbitmq-ingress` — allows AMQP traffic from the Ingestion API
and Processing Worker, plus Prometheus access to RabbitMQ metrics.
- `postgres-exporter-ingress` — allows Prometheus to scrape
PostgreSQL Exporter metrics.

The policies are defined as Helm templates and deployed
through Argo CD GitOps reconciliation.

### Scope and Limitations

The current implementation restricts ingress traffic only;
egress traffic is not restricted by these policies.
The RabbitMQ management endpoint is not included in the permitted ingress rules.
The default-deny policy applies to the selected Pods in `telemetry-system`;
it does not cover the `monitoring` namespace.
These policies define permitted traffic flows but do not, by themselves,
demonstrate end-to-end observability or prove that logs, metrics and alerts
are successfully delivered.

### Validation

The NetworkPolicy resources were deployed through Argo CD,
which reported the application as `Synced` and `Healthy`.
The application workloads remained Ready after synchronization.
Functional traffic-isolation checks were performed separately
from resource deployment.
The validation evidence should be interpreted according
to the specific connectivity tests captured in the project screenshots.
NetworkPolicy validation does not constitute end-to-end validation
of Prometheus scraping, log delivery to Loki, Grafana queries,
Alertmanager routing or webhook delivery.


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

### Kind Environment Note

During the final recovery validation, application-level
Prometheus targets—including ingestion-api, processing-service,
PostgreSQL Exporter, and RabbitMQ—were reported as `up`.
Several Kubernetes control-plane targets were reported as `down`
in the local Kind environment.
These targets were outside the scope of the successful application-level checks
and can be investigated separately
if full control-plane metrics coverage is required.

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
It provisions the local Kind environment, deploys the platform through Argo CD,
waits for application readiness, and runs automated smoke tests.
For a clean recovery, keep the bootstrap script outside the repository
and run it from the home directory:

```bash
cd "$HOME"
bash "$HOME/bootstrap-disaster-recovery.sh"
```

The script clones the repository into:

```bash
$HOME/production-cloud-platform/
```

Keeping the bootstrap script outside the repository allows it to bootstrap
a clean environment without depending on an existing local checkout.
The recovery process provisions:

```text
Docker
   ↓
kubectl and Kind
   ↓
Helm and Argo CD
   ↓
External Secrets Operator
   ↓
Prometheus / Grafana
   ↓
Loki / Promtail
   ↓
Production Cloud Platform
   ↓
Readiness checks and DR smoke tests
```

The final smoke-test suite validates Kubernetes resources, Argo CD health,
application metrics, PostgreSQL Exporter, Prometheus targets, Loki queries,
RabbitMQ, the alert webhook receiver, and NetworkPolicy behavior.

### Recovery Assets for Loki's MinIO Dependency

During the October 2026 disaster-recovery validation, the bootstrap
process encountered an unavailable upstream MinIO image reference
required by the Loki deployment configuration.

To make recovery reproducible in this environment, the project includes
a dedicated recovery directory:

`recovery/minio/`

It contains:

- Dockerfiles for the MinIO and `mc` container images.
- The required container entrypoint and CA certificate bundle.
- SHA-256 checksums for integrity verification.
- License texts and third-party notices.
- Loki-related configuration and dedicated recovery documentation.

The recovery assets and their intended use are documented in
[`recovery/minio/README.md`](recovery/minio/README.md).

This is a documented recovery workaround for an external image
availability issue. It does not replace upstream maintenance or
guarantee compatibility with every future Loki release.

The final bootstrap was subsequently completed successfully, including
Loki log-query validation and the broader disaster-recovery smoke tests.

### MinIO recovery binaries v1

The MinIO Server and MinIO Client (`mc`) binaries used to build the
project's recovery images are available in the
[MinIO recovery binaries v1 GitHub Release](https://github.com/av-crypto-security/production-cloud-platform/releases/tag/minio-recovery-binaries-v1).

- [MinIO Server binary](https://github.com/av-crypto-security/production-cloud-platform/releases/download/minio-recovery-binaries-v1/minio-binary)
- [MinIO Client (`mc`) binary](https://github.com/av-crypto-security/production-cloud-platform/releases/download/minio-recovery-binaries-v1/mc-binary)

The binaries were recovered from a running pod. Their byte-for-byte
identity with upstream release artifacts has not been independently
verified. See
[`recovery/minio/THIRD-PARTY-NOTICES.md`](recovery/minio/THIRD-PARTY-NOTICES.md)
for provenance and licensing information.


## Container Registry

Container images are published to GitHub Container Registry (GHCR).
Current application images:

```
ghcr.io/av-crypto-security/ingestion-api:v1.3.0
ghcr.io/av-crypto-security/processing-service:v1.4.0
ghcr.io/av-crypto-security/simulator:v1.0.0
ghcr.io/av-crypto-security/alert-webhook-receiver:v1.0.1
```

Versioned container images are referenced by the Kubernetes/Helm
deployment configuration.

The following pinned images are used by the Loki recovery configuration:

- **MinIO Server:** `ghcr.io/av-crypto-security/minio-recovery:release.2024-12-18t13-15-44z`
- **MinIO Client (`mc`):** `ghcr.io/av-crypto-security/mc-recovery:release.2024-11-21t17-21-54z`

Build instructions, checksums, and third-party notices are maintained
in [`recovery/minio/`](recovery/minio/).


## Helm

The Kubernetes manifests are packaged as a reusable Helm chart.

Current Helm features include:
- configurable image repositories and tags
- configurable replica counts
- parameterized ConfigMaps
- ESO-managed runtime Secrets referenced by Helm workloads
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
- Alembic database migrations
- HPA
- NetworkPolicy
- External Secrets Operator integration
- Kubernetes SecretStore and ExternalSecret resources
- RBAC-scoped access to out-of-band source Secrets
- ESO-managed application credentials
- ESO credential synchronization validation

### Finalization and Project Status

The planned platform features have been implemented and validated.
The final disaster-recovery bootstrap completed successfully,
including platform readiness checks and automated smoke tests.
The remaining work is limited to documentation review, evidence organization,
and the final repository audit.
No additional platform features are planned for this iteration.
Terraform infrastructure is maintained as a separate `cloud-infrastructure`
track and is not a dependency for freezing this project.
After the final documentation and repository checks,
the platform will be frozen as a portfolio project.
The next milestone is hands-on CKA preparation using Kubernetes concepts
and workloads demonstrated by this platform.


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

The active Helm chart no longer generates the application's PostgreSQL
and RabbitMQ Secrets from credential values in `values.yaml`.
Application credentials are sourced from Kubernetes Secrets provisioned outside
Git and synchronized by External Secrets Operator into ESO-managed target Secrets.
Secret values must not be committed to the repository or exposed
in terminal output, screenshots or documentation.
The `secret-source` namespace is protected by namespace-scoped Kubernetes RBAC
for the dedicated `eso-kubernetes-reader` ServiceAccount.
A dedicated NetworkPolicy for this namespace is not part
of the current implementation.
This project demonstrates secret synchronization and scoped
Kubernetes API access.
It is a local Kind portfolio environment,
not a claim of complete production security hardening.
The legacy Secret templates are retained as `.yaml.example`
reference artifacts outside the active Helm `templates/` directory
and are not rendered by the chart.


## Screenshots

Screenshots demonstrating the implemented platform and validation
evidence are available in:

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
