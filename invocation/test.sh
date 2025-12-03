#!/bin/bash
# set -euo pipefail

##########################
# CONSTANTS – CONFIGURE THESE AS NEEDED
##########################
SSH_PASSWORD="olaadeus"                     # SSH password for the Kubernetes cluster machines
MACHINE_USER="ubuntu"                     # SSH user (assumed to have sudo privileges for reboot)
MACHINES=("10.255.30.152" "10.255.30.196" "10.255.30.244")  # IPs of the 3 Kubernetes machines and the code-gen
WAIT_PERIOD=1                                    # Seconds to wait between each request
NAMESPACE="invocation"                       # Kubernetes namespace for helm chart deployment
WAIT_REBOOT=280                                  # Seconds to wait after rebooting the cluster machines
TESTS=("baseline" "enforcer-simple" "enforcer-complex")
NUMBER_TESTS=350
ENFORCER_QUEUE="ghcr.io/atnog/knative-flow-tagging/queue:latest"
BASELINE_QUEUE="gcr.io/knative-releases/knative.dev/serving/cmd/queue:v1.19.5"

# Base directory to store test results (trace file and pod logs)
BASE_RESULT_DIR="./results"
mkdir -p "$BASE_RESULT_DIR"

# Wait until all cluster nodes are Ready
wait_for_cluster() {
    echo "Waiting for all cluster nodes to be Ready..."
    while true; do
        not_ready=$(kubectl get nodes | tail -n 3 | grep -v " Ready" | wc -l)
        if [ "$not_ready" -eq 0 ]; then
            echo "All cluster nodes are Ready."
            break
        else
            echo "Some nodes are not Ready. Waiting 10 seconds..."
            sleep 10
        fi
    done
}

# Reboot all machines via SSH (requires sshpass)
reboot_machines() {
    echo "Rebooting cluster machines..."
    for machine in "${MACHINES[@]}"; do
        echo "Rebooting machine $machine..."
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no "$MACHINE_USER@$machine" "sudo reboot" &
    done
    echo "Waiting $WAIT_REBOOT seconds for machines to reboot..."
    sleep "$WAIT_REBOOT"
}

##########################
# MAIN LOOP: TEST RUNS WITH DIFFERENT PARAMETERS
##########################

result_trace_file="${BASE_RESULT_DIR}/requests_trace.txt"
for test in ${TESTS[@]}; do
    ##########################
    # 1. REBOOT CLUSTER MACHINES AND WAIT FOR CLUSTER TO BE READY
    ##########################
    reboot_machines
    wait_for_cluster

    while true; do
        kubectl create namespace $NAMESPACE
        if [ "$?" -eq 0 ]; then
            break
        else
            echo "Namespace not created with success; trying again..."
            sleep 60
        fi
    done

    if [[ $test == "enforcer-simple" ]]; then
        kubectl patch configmap config-deployment \
            -n knative-serving \
            --type merge \
            -p '{"data": {"queue-sidecar-image": "'$ENFORCER_QUEUE'"}}'

        export ALLOWED_PATH='[{"type": "sequence", "value": [{"type": "event", "value": {"name": "triggerEvent", "source": "entry-point", "type": "http.request.received", "kind": "consumed"}}, {"type": "function:expression", "value": null}, {"type": "function:knative", "value": {"operation": "f1"}}]}]'
        yq eval '.spec.template.metadata.annotations."qpoption.knative.dev/flow-config-allowed_json_flows" = strenv(ALLOWED_PATH)' -i application/kubernetes.yaml
    elif [[ $test == "enforcer-complex" ]]; then
        kubectl patch configmap config-deployment \
            -n knative-serving \
            --type merge \
            -p '{"data": {"queue-sidecar-image": "'$ENFORCER_QUEUE'"}}'

        export ALLOWED_PATH='[{"type": "sequence", "value": [{"type": "event", "value": {"name": "triggerEvent", "source": "entry-point", "type": "http.request.received", "kind": "consumed"}}, {"type": "function:expression", "value": null}, {"type": "function:knative", "value": {"operation": "f1"}}, {"type": "event", "value": {"trigger": {"name": "uploadPhoto", "type": "photo.database.upload", "kind": "produced"}, "result": {"name": "newPhoto", "source": "database-dummy", "type": "photo.database.new", "kind": "consumed"}}}, {"type": "function:knative", "value": {"operation": "f4"}}, {"type": "function:knative", "value": {"operation": "f5"}}, {"type": "event", "value": {"trigger": {"name": "verification", "type": "info.database.verification", "kind": "produced"}, "result": {"name": "resultVerification", "source": "database-dummy", "type": "info.database.result", "kind": "consumed"}}}, {"type": "function:knative", "value": {"operation": "f7"}}, {"type": "function:knative", "value": {"operation": "f6"}}, {"type": "function:knative", "value": {"operation": "f8"}}, {"type": "event", "value": {"trigger": {"name": "client", "type": "info.database.client", "kind": "produced"}, "result": {"name": "resultClient", "source": "database-dummy", "type": "info.database.resultClient", "kind": "consumed"}}}, {"type": "parallel", "value": [{"type": "sequence", "value": [{"type": "function:knative", "value": {"operation": "f9"}}]}, {"type": "sequence", "value": [{"type": "function:knative", "value": {"operation": "f10"}}]}, {"type": "sequence", "value": [{"type": "function:knative", "value": {"operation": "f11"}}]}]}, {"type": "function:expression", "value": null}, {"type": "parallel", "value": [{"type": "sequence", "value": [{"type": "function:knative", "value": {"operation": "function-b"}}, {"type": "function:knative", "value": {"operation": "function-c"}}], "loop": true}]}, {"type": "function:expression", "value": null}]}]'
        yq eval '.spec.template.metadata.annotations."qpoption.knative.dev/flow-config-allowed_json_flows" = strenv(ALLOWED_PATH)' -i application/kubernetes.yaml
    else
        kubectl patch configmap config-deployment \
            -n knative-serving \
            --type merge \
            -p '{"data": {"queue-sidecar-image": "'$BASELINE_QUEUE'"}}'
    fi

    for (( i=1; i<=NUMBER_TESTS; i++ )); do
        cd application/

        start_invocation=$(date +%s%3N)
        kubectl apply -f kubernetes.yaml
        kubectl wait --for=condition=ready ksvc function -n $NAMESPACE --timeout=1200s
        end_invocation=$(date +%s%3N)

        sleep "$WAIT_PERIOD"

        start_termination=$(date +%s%3N)
        pod=$(kubectl get pods -l serving.knative.dev/service=function -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
        kubectl delete -f kubernetes.yaml
        kubectl wait --for=delete pod/$pod -n $NAMESPACE --timeout=1200s
        end_termination=$(date +%s%3N)
        cd ../

        echo "$test,$i,$start_invocation,$end_invocation,$start_termination,$end_termination" >> "$result_trace_file"

        sleep "$WAIT_PERIOD"

        # REMOVE EVERYTHING BEFORE NEXT ITERATION
        kubectl delete $NAMESPACE &
        sleep 3
        kubectl get namespace "$NAMESPACE" -o json | jq 'del(.spec.finalizers) | .spec.finalizers=[] | del(.status)' > /tmp/ns.json
        kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f /tmp/ns.json
    done

    git add .
    git commit -s -m "new invocation results for $test"
    git push
done

echo "All tests completed."
