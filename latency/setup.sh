#!/bin/bash
kubectl patch configmap config-observability -n knative-serving --type merge -p \
    '{"data":{"logging.enable-request-log": "true"}}'
    # '{"data":{"request-metrics-protocol":"http/protobuf","request-metrics-endpoint":"http://otel-collector.otel.svc.cluster.local:4318/v1/metrics", "logging.enable-request-log": "true"}}'
    