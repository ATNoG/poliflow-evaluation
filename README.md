# PoliFlow Evaluation

This repository holds the preliminary tests made for the PoliFlow Enforcer for the article "PoliFlow: Inferring Control-Flow Policies from Serverless Workflows."

The `invocation` directory has the script for the `Deployment time` and `Teardown time` tests, while the `latency` directory holds the ones for the `Latencies` evaluations (for the `Refund` and `Valve` applications, as well as the ones for the sequences of 70 functions (`long-sequence`) and of 70 parallel states (`long-parallel`)).

## Note

This version of the repository has the container images registries name redacted, as the article was submitted to a double-blind review.
The expression `<organization>` is, therefore, to be updated with the actual organization to which we uploaded our images.
Nevertheless, the registries can also be changed to any other and the images built (using the `build.sh` scripts) from scratch for anyone trying to reproduce our results.
