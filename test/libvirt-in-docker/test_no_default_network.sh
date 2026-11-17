#!/usr/bin/env bash
# Scenario "test_no_default_network": libvirt-in-docker installed on fedora:44, a distribution with the modular
# daemons, with defaultNetwork false ("defaultNetwork disabled", "Modular distribution").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the start check exits zero" "${LID_CHECK}"
check "the layout is modular, and its six daemons and virtlogd run" \
  bash -c "test \"\$(record_field layout)\" = modular && layout_daemons_run"
check "the network default is defined and inactive" network_is_defined_and_inactive
check "the start record says why the network is inactive" \
  test "$(record_field defaultNetwork)" = "inactive (defaultNetwork is false)"
check "a software-emulated guest without a network reaches the running state" start_emulated_guest none
check "the guest is removed" remove_guest
check "the developer can start the network" virsh net-start default
check "the network default is active after that" network_is_active

reportResults
