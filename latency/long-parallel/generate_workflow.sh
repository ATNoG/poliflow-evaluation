#!/bin/bash

# Number of parallel iterations
n=$1
output_file="workflow/src/main/resources/workflow.sw.yaml"

# Create directory if it doesn't exist
mkdir -p "$(dirname "$output_file")"

# Clear the output file
> $output_file

# Static workflow header
cat <<'EOF' >> $output_file
id: long_parallel
name: Long parallel
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

  - name: merge-results
    type: expression
    operation: |
      def deepmerge($a; $b):
        if $a == null then $b
        elif $b == null then $a
        elif $b | type == "object" then
          reduce ($b | to_entries[]) as $kv ($a;
            .[$kv.key] = deepmerge(.[$kv.key]; $kv.value)
          )
        elif $b | type == "array" then
          if $a | type == "array" then
            ($a | length) as $la |
            ($b | length) as $lb |
            (if $la < $lb then $la else $lb end) as $minlen |
            reduce range(0; $minlen) as $i (
              { ok: true, prefix: [] };
              if .ok and ($a[$i] == $b[$i]) then
                { ok: true, prefix: (.prefix + [$a[$i]]) }
              else
                { ok: false, prefix: .prefix }
              end
            ) as $res |
            ($res.prefix) as $prefix |
            ($prefix | length) as $pLen |
            ([ range($pLen; $la) | $a[.] ]) as $tailA |
            ([ range($pLen; $lb) | $b[.] ]) as $tailB |
            ($prefix + $tailA + $tailB)
          else
            $b
          end
        else
          $b
        end;

      { _result: reduce (to_entries[] | select(.key | startswith("branch-"))) as $item ({};
          deepmerge(.; $item.value)
        )
      }
EOF

# Generate 2*n functions f1 ... f2n
for ((i=1; i<=2*n; i++)); do
cat <<EOF >> $output_file
  - name: f$i
    type: custom
    operation: knative:services.v1.serving.knative.dev/f$i?method=POST
EOF
done

# Add entry-event state
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
    transition: parallel-1
EOF

# Add parallel states and merge-results states
for ((i=1; i<=n; i++)); do
  f_left=$((2*i-1))
  f_right=$((2*i))

  # Parallel state
  cat <<EOF >> $output_file

  - name: parallel-$i
    type: parallel
    branches:
      - name: f$f_left
        actions:
          - functionRef: f$f_left
            actionDataFilter:
              fromStateData: "\${ ._original }"
              results: "\${ {\"branch-f$f_left\": .} }"
      - name: f$f_right
        actions:
          - functionRef: f$f_right
            actionDataFilter:
              fromStateData: "\${ ._original }"
              results: "\${ {\"branch-f$f_right\": .} }"
    stateDataFilter:
      input: "\${ { _original: . } }"
    transition: merge-results-$i

  - name: merge-results-$i
    type: operation
    actions:
      - functionRef: merge-results
    stateDataFilter:
      output: "\${ ._result }"
EOF

  # Transition to next parallel or end
  if [[ $i -lt $n ]]; then
    echo "    transition: parallel-$((i+1))" >> $output_file
  else
    echo "    end: true" >> $output_file
  fi
done
