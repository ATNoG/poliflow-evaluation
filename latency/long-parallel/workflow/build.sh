#!/bin/bash

REGISTRY=ghcr.io/atnog/poliflow-evaluation/long-parallel

kubectl delete ksvc workflow -n long-parallel
export MAVEN_OPTS="-Xss16m"
kn workflow quarkus build --image=workflow --jib
docker image tag workflow $REGISTRY/workflow
docker push $REGISTRY/workflow
kn workflow quarkus deploy  --path ./src/main/kubernetes
