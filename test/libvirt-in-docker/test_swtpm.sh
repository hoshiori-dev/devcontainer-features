#!/usr/bin/env bash
# Scenario "test_swtpm": libvirt-in-docker installed on debian:13 with swtpm true ("swtpm enabled").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "swtpm and swtpm_setup are installed" swtpm_installed
check "the start check exits zero" "${LID_CHECK}"
check "the network default is active" network_is_active

reportResults
