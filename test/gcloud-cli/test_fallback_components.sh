#!/usr/bin/env bash
# Scenario test_fallback_components: opensuse/leap:16.0 (archive fallback route) with version 593.0.0 and
# components kubectl,alpha.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "gcloud reports pinned fallback version 593.0.0" \
  bash -c 'gcloud version | grep -qx "Google Cloud SDK 593.0.0"'
check "gcloud is installed from the fallback archive directory" \
  test "$(readlink -f "$(command -v gcloud)")" = /usr/local/share/google-cloud-sdk/bin/gcloud
check "kubectl component is linked on PATH and runs" kubectl version --client
check "alpha component group works" gcloud alpha --help
check "no staging directory remains" bash -c '! compgen -G "/usr/local/share/.gcloud-cli-install.*"'

reportResults
