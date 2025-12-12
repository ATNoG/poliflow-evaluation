#!/bin/bash

REGISTRY=ghcr.io/atnog/poliflow-evaluation/valve

kubectl delete ksvc workflow -n valve
kn workflow quarkus build --image=workflow --jib
docker image tag workflow $REGISTRY/workflow
docker push $REGISTRY/workflow
kn workflow quarkus deploy  --path ./src/main/kubernetes
