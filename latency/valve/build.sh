#!/bin/bash

REGISTRY=ghcr.io/<organization>/poliflow-evaluation/valve
paths=(entry-point sample-function database-dummy result)

for p in ${paths[@]}; do
    cd $p
    docker build -t="$REGISTRY/$p" .
    docker push "$REGISTRY/$p"
    cd ../
done
