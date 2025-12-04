#!/bin/bash

REGISTRY=ghcr.io/atnog/knative-workflow-apps-kit/long-parallel

kubectl delete ksvc workflow -n long-parallel
export MAVEN_OPTS="-Xmx16G -Xms4G -XX:MaxMetaspaceSize=4G"
kn workflow quarkus build --image=workflow --jib
docker image tag workflow $REGISTRY/workflow
docker push $REGISTRY/workflow
kn workflow quarkus deploy  --path ./src/main/kubernetes
