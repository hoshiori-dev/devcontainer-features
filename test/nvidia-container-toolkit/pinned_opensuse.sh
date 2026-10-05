#!/usr/bin/env bash
# Scenario: version pinned to 1.19.1, an exact release older than the newest, on the image scenarios.json names.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "nvidia-ctk runs for the remote user" nvidia-ctk --version
check "nvidia-container-cli runs for the remote user" nvidia-container-cli --version
check "all four packages are at 1.19.1" packages_at "1.19.1-1"
check "nvidia-ctk reports 1.19.1" ctk_reports "1.19.1"
check "the configured repository is NVIDIA's stable repository, signature-checked against a local copy of the key" \
  repository_file_is_expected
check "the key file holds only NVIDIA's pinned key" key_is_pinned

reportResults
