# Production Cloud Platform (platform engineering lifecycle)

Production-style infrastructure monitoring and telemetry processing platform demonstrating Kubernetes orchestration, CI/CD automation, observability and operational reliability practices.

---

## Current Development Status

This repository is actively maintained and continuously expanded as part of a production-style engineering portfolio.

Recent focus areas include:

* cloud-native infrastructure and platform engineering;
* Kubernetes and container orchestration;
* CI/CD automation and GitOps workflows;
* observability, monitoring and reliability engineering;
* secure networking and infrastructure security.

Some components and documentation are currently being updated and refactored to reflect ongoing improvements and new functionality.

Planned enhancements include:

* end-to-end CI/CD pipelines;
* Helm-based deployments;
* GitOps workflows with ArgoCD;
* infrastructure observability and alerting;
* production-style service deployment lifecycle.

The repository remains functional and serves as a continuously evolving engineering project.

---

## Overview

Production-style cloud platform demonstrating the complete service delivery lifecycle, including infrastructure provisioning, containerization, Kubernetes orchestration, CI/CD automation, GitOps deployment workflows, observability and operational reliability practices.

The project simulates telemetry ingestion and processing for infrastructure monitoring systems and is being developed incrementally using production engineering approaches.

The system models a simplified monitoring workflow for industrial and technical infrastructure environments.

---

## Architecture

```text
                    ┌─────────────────────┐
                    │ Sensor Simulators   │
                    │ Python generators   │
                    └─────────┬───────────┘
                              │ HTTP JSON
                              ▼
                    ┌─────────────────────┐
                    │ NGINX Ingress       │
                    └─────────┬───────────┘
                              ▼
                    ┌─────────────────────┐
                    │ FastAPI API         │
                    │ validation/auth     │
                    └─────────┬───────────┘
                              ▼
                    ┌─────────────────────┐
                    │ Redis Queue         │
                    │ async buffering     │
                    └─────────┬───────────┘
                              ▼
                    ┌─────────────────────┐
                    │ Telemetry Worker    │
                    │ processing          │
                    │ anomaly detection   │
                    └─────────┬───────────┘
                              ▼
                    ┌─────────────────────┐
                    │ PostgreSQL          │
                    │ telemetry/events    │
                    └─────────┬───────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
 ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
 │ Prometheus     │ │ Loki           │ │ OpenTelemetry  │
 │ metrics        │ │ logs           │ │ traces         │
 └────────┬───────┘ └────────┬───────┘ └────────┬───────┘
          └──────────────────┼──────────────────┘
                             ▼
                    ┌─────────────────────┐
                    │ Grafana             │
                    │ dashboards/alerts   │
                    └─────────────────────┘


        ┌──────────────────────────────────────┐
        │ Kubernetes (k3s/kind/EKS/GKE)        │
        │ deployments/services/HPA/secrets     │
        └──────────────────────────────────────┘


        ┌──────────────────────────────────────┐
        │ GitHub Actions CI/CD                 │
        │ build/test/deploy                    │
        └──────────────────────────────────────┘


        ┌──────────────────────────────────────┐
        │ Terraform IaC                        │
        │ cluster/network/storage              │
        └──────────────────────────────────────┘
```
Prometheus, Grafana and Loki provide centralized monitoring, metrics collection and log aggregation.

## Platform workflow
1. Monitoring devices or external systems submit telemetry events through the ingestion API
2. The API validates and queues telemetry data in Redis
3. Worker services asynchronously process telemetry events
4. Processing results and alert metadata are stored in PostgreSQL
5. Prometheus and Loki collect operational metrics and logs
6. Grafana dashboards provide observability into platform health and workload processing

## Operational Goals
- rolling deployments
- self-healing workloads
- horizontal scaling
- centralized logging
- infrastructure reproducibility
- deployment automation

## Core Components
### Infrastructure
Terraform
VPC networking
IAM configuration
Security groups
Environment isolation
### Kubernetes Platform
Deployments
Services
Ingress
Autoscaling
Rolling updates
Health checks
### CI/CD
GitHub Actions
Automated build pipelines
Container image deployment
Rollback workflows
### Observability
Prometheus
Grafana
Loki
Centralized logging
Alerting
### Security
TLS
Kubernetes secrets
Network policies
Secure service communication

## Repository Structure
```
production-cloud-platform/
│
├── infrastructure/
│   ├── terraform/
│   ├── helm/
│   └── scripts/
│
├── kubernetes/
│   ├── base/
│   ├── monitoring/
│   ├── ingress/
│   └── applications/
│
├── services/
│   ├── api/
│   ├── worker/
│   ├── simulator/
│   └── shared/
│
├── observability/
│   ├── grafana/
│   ├── prometheus/
│   ├── loki/
│   └── otel/
│
├── docs/
│   ├── architecture/
│   ├── operations/
│   ├── runbooks/
│   └── threat-model/
│
├── .github/workflows/
│
├── screenshots/
│
├── Makefile
├── docker-compose.yaml
└── README.md
```

## Failure Recovery Scenarios

The platform includes operational scenarios for:
Pod failure recovery
Rolling deployments
Failed deployment rollback
Node failure handling
Autoscaling under load

## Screenshots

Architecture diagrams, dashboards and deployment screenshots are located in:

`screenshots/`

## Documentation

Detailed documentation is available in:

`docs/`

Including:

architecture
deployment workflow
operations
troubleshooting
threat model

## Technology Stack
Kubernetes
Terraform
Docker
GitHub Actions
Prometheus
Grafana
PostgreSQL
Redis
## License
MIT License
