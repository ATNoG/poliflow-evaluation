#!/bin/bash
# set -euo pipefail

##########################
# CONSTANTS – CONFIGURE THESE AS NEEDED
##########################
SSH_PASSWORD="olaadeus"                     # SSH password for the Kubernetes cluster machines
MACHINE_USER="ubuntu"                     # SSH user (assumed to have sudo privileges for reboot)
EXTERNAL_IP="10.255.30.152"
MACHINES=("10.255.30.152" "10.255.30.196" "10.255.30.244")  # IPs of the 3 Kubernetes machines and the code-gen
WAIT_PERIOD=3                                    # Seconds to wait between each request
NAMESPACES=("long-sequence" "long-parallel")      # "refund" "valve" "long-sequence" "long-parallel"
WAIT_REBOOT=280                                  # Seconds to wait after rebooting the cluster machines
TESTS=("baseline" "enforce")
NUMBER_TESTS=350
ENFORCER_QUEUE="ghcr.io/<organization>/poliflow-enforcer/queue:latest"
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
    for namespace in ${NAMESPACES[@]}; do
        ##########################
        # 1. REBOOT CLUSTER MACHINES AND WAIT FOR CLUSTER TO BE READY
        ##########################
        reboot_machines
        wait_for_cluster
        
        test_timestamp=$(date +%Y%m%d%H%M%S)
        test_dir="${BASE_RESULT_DIR}/test-${test}_namespace-${namespace}_${test_timestamp}"
        mkdir -p "$test_dir"
        if [[ $test == "enforce" ]]; then
            kubectl patch configmap config-deployment \
                -n knative-serving \
                --type merge \
                -p '{"data": {"queue-sidecar-image": "'$ENFORCER_QUEUE'"}}'
        else
            kubectl patch configmap config-deployment \
                -n knative-serving \
                --type merge \
                -p '{"data": {"queue-sidecar-image": "'$BASELINE_QUEUE'"}}'
        fi

        while true; do
            kubectl create namespace $namespace
            if [ "$?" -eq 0 ]; then
                break
            else
                echo "Namespace not created with success; trying again..."
                sleep 60
            fi
        done

        cd $namespace/
        kubectl apply -f kubernetes.yaml
        if [[ $namespace == "long-sequence" || $namespace == "long-parallel" ]]; then
            kubectl apply -f functions.yaml
        fi
        cd ..

        echo "Waiting for application to be ready (only one pod starting with 'result')..."
        if [[ $namespace == "refund" ]]; then
            needed_pods=8
        elif [[ $namespace == "valve" ]]; then
            needed_pods=15
        elif [[ $namespace == "long-sequence" ]]; then
            needed_pods=72
        elif [[ $namespace == "long-parallel" ]]; then
            needed_pods=142
        fi
        while true; do
            # Count running pods
            number_running=$(kubectl get pods -n "$namespace" | grep -c 'Running')
            # Count terminating pods
            number_terminating=$(kubectl get pods -n "$namespace" | grep -c 'Terminating')

            if [[ $number_running -eq $needed_pods && $number_terminating -eq 0 ]]; then
                echo "Application is ready: $number_running running pods, no terminating pods."
                break
            else
                echo "Waiting: $number_running running pods, $number_terminating terminating pods (need $needed_pods running). Retrying in 5 seconds..."
                sleep 5
            fi
        done

        sleep $WAIT_REBOOT

        echo "Starting tests"
        for (( i=1; i<=NUMBER_TESTS; i++ )); do
            if [[ $namespace == "valve" ]]; then
                data='{"postListing": true}'
            else
                data='{}'
            fi
            curl http://entry-point.$namespace.$EXTERNAL_IP.sslip.io --data "$data" -H 'Content-Type: application/json' -v

            sleep "$WAIT_PERIOD"

            if [[ $test == "enforce" && $namespace == "long-parallel" ]]; then
                sleep 10
            fi
        done

        sleep $WAIT_REBOOT

        echo "Saving logs from pods"
        pods_to_log=$(kubectl get pods -n "$namespace" --no-headers -o custom-columns=NAME:.metadata.name || true)
        for pod in $pods_to_log; do
            pod_log_file_queue="${test_dir}/pod_${pod}_queue_proxy_logs.txt"
            echo "Saving logs for pod $pod and container queue-proxy to $pod_log_file_queue"
            kubectl logs "$pod" -c queue-proxy -n "$namespace" > "$pod_log_file_queue"

            pod_log_file_user="${test_dir}/pod_${pod}_user_container_logs.txt"
            echo "Saving logs for pod $pod and container user-container to $pod_log_file_user"
            kubectl logs "$pod" -c user-container -n "$namespace" > "$pod_log_file_user"

            # Check if the pod has a previous instance and save its logs
            # echo "Saving logs for previous instance of pod $pod" >> "$pod_log_file"
            # kubectl logs "$pod" -c user-container -n "$namespace" --previous >> "$pod_log_file"
        done

        git add .
        git commit -s -m "new latency results for $test"
        git push

        # REMOVE EVERYTHING BEFORE NEXT ITERATION
        cd $namespace/
        kubectl delete -f kubernetes.yaml
        if [[ $namespace == "long-sequence" || $namespace == "long-parallel" ]]; then
            kubectl delete -f functions.yaml
        fi
        cd ..
        kubectl delete namespace $namespace
    done
done

echo "All tests completed."
