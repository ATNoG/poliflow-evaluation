#!/bin/bash

REGISTRY=ghcr.io/atnog/poliflow-evaluation/refund
paths=(entry-point sample-function database-dummy result)

for p in ${paths[@]}; do
    cd $p
    docker build -t="$REGISTRY/$p" .
    docker push "$REGISTRY/$p"
    cd ../
done
