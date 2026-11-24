#!/usr/bin/env bash
# Scenario test_components_apt: debian:12 with components kubectl,gke-gcloud-auth-plugin,alpha.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "gcloud runs as the remote user" gcloud version
check "kubectl is installed on PATH" kubectl version --client
check "gke-gcloud-auth-plugin is installed on PATH" gke-gcloud-auth-plugin --version
check "gcloud alpha command group works" gcloud alpha --help

reportResults
