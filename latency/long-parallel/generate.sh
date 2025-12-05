#!/bin/bash

# Number of *parallel states* to generate
n=$1
output_file="functions.yaml"
namespace="long-parallel"

# Clear the output file
> $output_file

# Base steps for the sequence: event + expression
sequence_steps='{"type":"event","value":{"name":"triggerEvent","source":"entry-point","type":"http.request.received","kind":"consumed"}},{"type":"function:expression","value":null}'

# We have 2*n functions total
total=$((n * 2))

for ((i=1; i<=total; i++)); do

  # Every 2 functions -> add one parallel block
  if (( i > 1 && (i % 2) == 1 )); then
    # Example: when i = 3, we group (1,2)
    fA=$((i - 2))
    fB=$((i - 1))

    parallel_block="{\"type\":\"parallel\",\"value\":[{\"type\":\"sequence\",\"value\":[{\"type\":\"function:knative\",\"value\":{\"operation\":\"f$fA\"}}]},{\"type\":\"sequence\",\"value\":[{\"type\":\"function:knative\",\"value\":{\"operation\":\"f$fB\"}}]}]}"

    # Append to sequence steps
    sequence_steps="$sequence_steps,$parallel_block"
  fi

  # Wrap in top-level sequence
  sequence_flow="{\"type\":\"sequence\",\"value\":[$sequence_steps]}"

  # Emit Service YAML
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
        - image: ghcr.io/atnog/knative-workflow-apps-kit/$namespace/sample-function
---
EOF
done
