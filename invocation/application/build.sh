#!/bin/bash

REGISTRY=ghcr.io/atnog/poliflow-evaluation/invocation
paths=(sample-function)

for p in ${paths[@]}; do
    cd $p
    docker build -t="$REGISTRY/$p" .
    docker push "$REGISTRY/$p"
    cd ../
done
