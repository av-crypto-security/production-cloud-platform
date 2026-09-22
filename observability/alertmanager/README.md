### Alerting

Platform alerting is implemented through PrometheusRule resources
and Alertmanager. Platform alerts are routed through an AlertmanagerConfig
resource to an in-cluster HTTP webhook receiver.

The demonstrated alert lifecycle is:

INACTIVE → PENDING → FIRING → RESOLVED

The webhook receiver logs notification events to stdout for delivery
validation. It is a demonstration component and does not provide
persistent notification storage.
