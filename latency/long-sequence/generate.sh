#!/bin/bash

# Number of services to generate
n=$1
output_file="functions.yaml"
namespace="long-sequence"

# Clear the output file
> $output_file

# Base steps for the sequence
sequence_steps='{"type":"event","value":{"name":"triggerEvent","source":"entry-point","type":"http.request.received","kind":"consumed"}},{"type":"function:expression","value":null}'

for ((i=1; i<=n; i++)); do
  if [[ $i -gt 1 ]]; then
    # Append the new knative function step to the flat list
    sequence_steps="$sequence_steps,{\"type\":\"function:knative\",\"value\":{\"operation\":\"f$((i-1))\"}}"
  fi

  # Wrap in top-level sequence
  sequence_flow="{\"type\":\"sequence\",\"value\":[$sequence_steps]}"

  # Write the service YAML
  cat <<EOF >> $output_file
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: f$i
  namespace: $namespace
  labels:
    networking.knative.dev/visibility: cluster-local
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: "1"
        autoscaling.knative.dev/max-scale: "1"
        qpoption.knative.dev/flow-config-allowed_json_flows: |
          [$sequence_flow]
        qpoption.knative.dev/flow-activate: enable
    spec:
      containers:
        - image: ghcr.io/atnog/poliflow-evaluation/$namespace/sample-function
---
EOF
done
