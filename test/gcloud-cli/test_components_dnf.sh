#!/usr/bin/env bash
# Scenario test_components_dnf: fedora:44 with components kubectl,gke-gcloud-auth-plugin,beta.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "gcloud runs as the remote user" gcloud version
check "kubectl is installed on PATH" kubectl version --client
check "gke-gcloud-auth-plugin is installed on PATH" gke-gcloud-auth-plugin --version
check "gcloud beta command group works" gcloud beta --help

reportResults
