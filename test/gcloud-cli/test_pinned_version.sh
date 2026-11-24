#!/usr/bin/env bash
# Scenario test_pinned_version: ubuntu24.04 (remoteUser vscode) pinned to 590.0.0 with kubectl.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "gcloud reports exact pinned version 590.0.0" \
  bash -c 'gcloud version | grep -qx "Google Cloud SDK 590.0.0"'
# Single-quoted format string passes literal ${Version} placeholder to dpkg-query.
# shellcheck disable=SC2016
check "kubectl package is pinned to 1:590.0.0-0" \
  bash -c 'dpkg-query -W -f="${Version}" kubectl | grep -qx "1:590.0.0-0"'
check "kubectl client runs as vscode" kubectl version --client

reportResults
