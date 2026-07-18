# Production Cloud Platform (platform engineering lifecycle)

Production-style cloud platform demonstrating the complete software delivery lifecycle:
Docker -> Kubernetes -> GHCR -> Helm -> GitHub Actions -> ArgoCD
Production-style cloud platform implementing a complete GitOps delivery workflow.

---

## GitOps Workflow

```text
Git Commit -> Git Push -> GitHub -> GitHub Actions -> Container Images (GHCR) -> ArgoCD detects Git changes -> Helm renders manifrests -> Kubernetes reconciles desired state
```
Implemented end-to-end GitOps delivery using GitHub Actions, GitHub Container Registry, Helm and ArgoCD with automatic synchronization and self-healing reconciliation.

---

## Current Development Status

This repository is actively maintained and continuously expanded as part of a production-style engineering portfolio.

---
Recently implemented:

- GitHub Container Registry (GHCR)
- Helm chart packaging
- GitHub Actions CI pipeline
- ArgoCD GitOps deployment
- Automated synchronization from Git to Kubernetes
---

Recent focus areas include:

* observability, monitoring and reliability engineering;
* secure networking and infrastructure security.

Some components and documentation are currently being updated and refactored to reflect ongoing improvements and new functionality.

Planned enhancements include:

* Prometheus metrics
* Grafana dashboards
* Loki log aggregation
* Alertmanager
* Redis integration
* Terraform infrastructure provisioning

The repository remains functional and serves as a continuously evolving engineering project.

---

## Overview

Production-style cloud platform demonstrating the complete service delivery lifecycle, including infrastructure provisioning, containerization, Kubernetes orchestration, CI/CD automation, GitOps deployment workflows, observability and operational reliability practices.
The project simulates telemetry ingestion and processing for infrastructure monitoring systems and is being developed incrementally using production engineering approaches.
The system models a simplified monitoring workflow for industrial and technical infrastructure environments.
GitOps delivery is implemented using ArgoCD. Kubernetes resources are managed through Helm charts stored in Git, allowing automatic synchronization between the repository and the cluster.
---

## Security Notice

This repository uses demonstration credentials.
Kubernetes Secrets included in the repository are intended only for testing environments and must be replaced with properly managed secrets in production deployments.
Development secrets are stored in Helm values for demonstration purposes only.
Production deployments should use GitHub Secrets, External Secrets Operator or dedicated secret management solutions.

## Container Registry

Container images are published to GitHub Container Registry (GHCR).
Current images:
- `ghcr.io/av-crypto-security/ingestion-api:v1.0,0`
- `ghcr.io/av-crypto-security/processing-service:v1.0.1`
- `ghcr.io/av-crypto-security/simulator:v1.0.0`
The Kubernetes manifests reference these images directly, allowing clean cluster provisioning.
This approach mirrors common production deployment workflows where Kubernetes pulls versioned container images from a remote registry.

## Helm Deployment

The Kubernetes manifests are packaged as a reusable Helm Chart.
Current Helm features include:
- configurable image repository and tags
- configurable replica count
- parameterized ConfigMaps
- parameterized Secrets
- namespace abstraction using `.Release.Namespace`
This enables reusable deployments across multiple Kubernetes environments.

## CI/CD Pipeline

```text
Developer
    |
Git Push -> GitHub Repository -> GitHub Actions -> GHCR -> ArgoCD (GitOps) -> Helm Chart -> Kubernetes Cluster
```
 
## Target Production Architecture

The following diagram represents the target production architecture that is being implemented incrementally.
Current development focuses on telemetry ingestion, data storage and service deployment lifecycle components.
Additional platform capabilities such as GitOps workflows, observability, service orchestration and infrastructure automation are introduced in subsequent development stages.

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

## Current Implementation Status

Implemented:

- Sensor Simulator service
- FastAPI Ingestion API
- PostgreSQL Persistence
- Telemetry Processing Worker
- Docker Containerization
- Docker Compose Deployment
- Kubernetes Deployment (Kind)
- ConfigMaps and Secrets
- Stateful PostgreSQL Storage
- GitHub Container Registry (GHCR) integration
- Helm Chart
- GitHub Actions CI Pipeline
- ArgoCD GitOps
- Automatic synchronization (Git -> Kubernetes)

Planned:

- Prometheus and Grafana observability stack
- Redis

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
- GitOps delivery
- automatic reconciliation
- declarative deployments

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
ArgoCD
Prometheus
Grafana
PostgreSQL
Redis
## License
MIT License
