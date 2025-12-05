#!/bin/bash

# Number of parallel iterations
n=$1
max_per_flow=20
output_dir="workflow/src/main/resources"
rm $output_dir/subflow*

mkdir -p "$output_dir"

############################################
### STEP 1 — Determine number of subflows ###
############################################

flows=$(( (n + max_per_flow - 1) / max_per_flow ))

############################################
### Helper: write merge-results function ###
############################################
write_merge_results() {
cat <<'EOF'
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
}

############################################
### STEP 2 — Generate main workflow        ###
############################################

main_file="$output_dir/workflow.sw.yaml"
> "$main_file"

cat <<'EOF' >> "$main_file"
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
EOF

write_merge_results >> "$main_file"

############################################
### Functions for ALL workflows (f1..f2n) ###
############################################
main_file_functions=$((max_per_flow*2))
if [[ $n -lt $max_per_flow ]]; then
  main_file_functions=$((n*2))
fi

for ((i=1; i<=main_file_functions; i++)); do
cat <<EOF >> "$main_file"
  - name: f$i
    type: custom
    operation: knative:services.v1.serving.knative.dev/f$i?method=POST
EOF
done

############################################
### ENTRY EVENT STATE                      ###
############################################
cat <<'EOF' >> "$main_file"

states:
  - name: entry-event
    type: event
    onEvents:
      - eventRefs:
          - triggerEvent
        actions:
        - functionRef: process-event
    stateDataFilter:
      output: "${ .transformed }"
    transition: parallel-1
EOF

############################################
### STEP 3 — Generate parallel states in main workflow ###
############################################

# How many iterations belong in the first/main workflow?
first_flow_count=$(( n < max_per_flow ? n : max_per_flow ))

for ((i=1; i<=first_flow_count; i++)); do
  f_left=$((2*i-1))
  f_right=$((2*i))
  next=$((i+1))

cat <<EOF >> "$main_file"

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

  if [[ $i -lt $first_flow_count ]]; then
    echo "    transition: parallel-$next" >> "$main_file"
  else
    if [[ $flows -gt 1 ]]; then
      echo "    transition: next-workflow" >> "$main_file"
    else
      echo "    end: true" >> "$main_file"
    fi
  fi
done

############################################
### STEP 4 — Add next-workflow state if needed ###
############################################

if [[ $flows -gt 1 ]]; then
cat <<EOF >> "$main_file"

  - name: next-workflow
    type: operation
    actions:
      - subFlowRef: subflow1
    end: true
EOF
fi

############################################
### STEP 5 — Generate Subflows            ###
############################################

for ((flow=1; flow<flows; flow++)); do
  subfile="$output_dir/subflow$flow.sw.yaml"
  > "$subfile"

  start_index=$((flow*max_per_flow + 1))
  end_index=$((start_index + max_per_flow - 1))
  if [[ $end_index -gt $n ]]; then
    end_index=$n
  fi

  cat <<EOF >> "$subfile"
id: subflow$flow
name: subflow$flow
version: '0.1.0'
specVersion: '0.8'
start: parallel-$start_index

functions:
EOF

  write_merge_results >> "$subfile"

  # function list (fX..fY) → two per parallel
  for ((i=start_index; i<=end_index; i++)); do
    f_left=$((2*i-1))
    f_right=$((2*i))

cat <<EOF >> "$subfile"
  - name: f$f_left
    type: custom
    operation: knative:services.v1.serving.knative.dev/f$f_left?method=POST
  - name: f$f_right
    type: custom
    operation: knative:services.v1.serving.knative.dev/f$f_right?method=POST
EOF
  done

  echo "" >> "$subfile"
  echo "states:" >> "$subfile"

  # parallel states in the subflow
  for ((i=start_index; i<=end_index; i++)); do
    f_left=$((2*i-1))
    f_right=$((2*i))
    next=$((i+1))

cat <<EOF >> "$subfile"
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

    if [[ $i -lt $end_index ]]; then
      echo "    transition: parallel-$next" >> "$subfile"
    else
      if (( flow < flows-1 )); then
        echo "    transition: next-workflow" >> "$subfile"
      else
        echo "    end: true" >> "$subfile"
      fi
    fi
  done

  if (( flow < flows-1 )); then
cat <<EOF >> "$subfile"

  - name: next-workflow
    type: operation
    actions:
      - subFlowRef: subflow$((flow+1))
    end: true
EOF
  fi

done
