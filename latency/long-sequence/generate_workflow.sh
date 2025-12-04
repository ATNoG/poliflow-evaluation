#!/bin/bash

n=$1
output_file="workflow/src/main/resources/workflow.sw.yaml"

# Create directory if it doesn't exist
mkdir -p "$(dirname "$output_file")"

# Start writing workflow YAML
cat <<EOF > $output_file
id: long_sequence
name: Long sequence
version: '0.1.0'
specVersion: '0.8'
start: entry-event

events:
  - name: triggerEvent
    type: http.request.received
    source: entry-point
    kind: consumed

functions:
  - name: process-event
    type: expression
    operation: |
      {
        transformed: (
          (
            .headers
            | to_entries
            | map(select(.key | ascii_downcase != "host"))
            | map({("HEADER_" + .key): .value})
            | add
          ) + .data
        )
      }
EOF

# Add all f{i} functions
for ((i=1; i<=n; i++)); do
cat <<EOF >> $output_file
  - name: f$i
    type: custom
    operation: knative:services.v1.serving.knative.dev/f$i?method=POST
EOF
done

# Start states section
cat <<EOF >> $output_file

states:
  - name: entry-event
    type: event
    onEvents:
      - eventRefs:
          - triggerEvent
        actions:
        - functionRef: process-event
    stateDataFilter:
      output: "\${ .transformed }"
    transition: f1
EOF

# Add function states
for ((i=1; i<=n; i++)); do
  next="f$((i+1))"
  if [[ $i -eq $n ]]; then
    # Last function ends the workflow
    cat <<EOF >> $output_file

  - name: f$i
    type: operation
    actions: 
      - functionRef: f$i
        actionDataFilter:
          toStateData: ._result
    stateDataFilter:
      output: ._result
    end: true
EOF
  else
    # Transition to next function
    cat <<EOF >> $output_file

  - name: f$i
    type: operation
    actions: 
      - functionRef: f$i
        actionDataFilter:
          toStateData: ._result
    stateDataFilter:
      output: ._result
    transition: $next
EOF
  fi
done
