#!/bin/bash

REGISTRY=ghcr.io/atnog/knative-workflow-apps-kit/long-parallel
paths=(entry-point sample-function)

for p in ${paths[@]}; do
    cd $p
    docker build -t="$REGISTRY/$p" .
    docker push "$REGISTRY/$p"
    cd ../
done
