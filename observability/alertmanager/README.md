# Alertmanager

Alertmanager is used for alert grouping, routing and notification
delivery in the Production Cloud Platform.

## Architecture

The implemented alerting flow is:

```text
Kubernetes
    |
    v
Prometheus
    |
    v
PrometheusRule
    |
    v
Alertmanager
    |
    v
AlertmanagerConfig
    |
    v
HTTP webhook receiver
    |
    v
Container logs
```

## Alert Rules

The platform currently defines custom Prometheus alerts for:

- PlatformPodNotReady
- PlatformTargetDown
- PlatformHighCPU
- PlatformHighMemory

Platform alerts are identified using:

`category=platform`

## AlertmanagerConfig

Platform alert routing is defined by the
`AlertmanagerConfig` resource:

`platform-webhook`

The configuration:

- matches category=platform
- groups alerts by namespace and alert name
- uses a 10 second group wait
- uses a 5 minute group interval
- uses a 12 hour repeat interval
- sends notifications to the platform webhook receiver
- sends resolved notifications

## Namespace Matching

The Alertmanager instance uses:
```yaml
alertmanagerConfigMatcherStrategy:
  type: OnNamespaceExceptForAlertmanagerNamespace
```
The `platform-webhook` `AlertmanagerConfig` is located in the
same namespace as Alertmanager (monitoring) and can therefore
process platform alerts originating from other namespaces, such as
`telemetry-system`.

This configuration is stored in:

`observability/alertmanager/values.yaml`

## Webhook Receiver

The notification receiver is implemented as a small Flask service
behind Gunicorn.

Source:

`observability/alertmanager/webhook-receiver/`

The receiver exposes:
```text
GET  /health
POST /alerts
```
Notification events are written to container stdout.

Example:
```
ALERTMANAGER NOTIFICATION status=firing
alertname=PlatformPodNotReady
severity=warning
namespace=telemetry-system
```
and:
```
ALERTMANAGER NOTIFICATION status=resolved
alertname=PlatformPodNotReady
severity=warning
namespace=telemetry-system
```

## Controlled Incident Validation

Alert delivery was validated using a temporary Kubernetes
Deployment with a readiness probe that intentionally fails.

Expected lifecycle:
```
INACTIVE
    |
    v
PENDING
    |
    v
FIRING
    |
    v
RESOLVED
```
The incident was observed in:

- Prometheus
- Alertmanager
- webhook receiver logs

The temporary test workload was removed after validation.

## Delivery Validation

The end-to-end path was verified as:
```
Prometheus -> Alertmanager -> AlertmanagerConfig -> Kubernetes Service -> webhook receiver -> Flask /alerts -> container logs
```
A direct HTTP test was also used to validate the webhook receiver
independently from Alertmanager.

## Limitations

The current webhook receiver is a demonstration notification
endpoint.

It:

- writes notification events to stdout
- does not persist notifications
- does not provide external paging or messaging
- is not intended to replace a production notification platform

A production implementation could integrate Alertmanager with
external notification and incident-management systems.
