#!/usr/bin/env bash
# Scenario "test_channel_lts": incus installed on debian:13 with channel lts-6.0. The repository definition names
# that channel, the installed Incus is of the 6.0 series, and its daemon starts and runs an instance ("Long-term
# support channel").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the repository definition names only the lts-6.0 channel" sources_name_channel lts-6.0
check "incus --version reports a version of the 6.0 series" bash -c 'incus --version | grep -q "^6\.0\."'
check "incus-base is installed from the Zabbly repository" zabbly_package_installed incus-base
check "the start check exits zero" "${INCUS_CHECK}"
check "an instance starts and gets an address on the managed bridge" instance_starts_with_address
check "the instance is removed" remove_instance

reportResults
