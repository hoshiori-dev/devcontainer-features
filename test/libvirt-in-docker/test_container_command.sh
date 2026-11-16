#!/usr/bin/env bash
# Scenario "test_container_command": libvirt-in-docker on an image built from debian:13 whose command, `sleep
# infinity`, stays the container's main process (overrideCommand false) and collects no ended processes ("Container
# command that collects nothing"). Without the init the feature requests, libvirtd would never answer here.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the container's first process is the init the feature requests" container_has_init
check "the image's own command runs under it" bash -c "tr '\0' ' ' </proc/1/cmdline | grep -q 'sleep infinity'"
check "the start check exits zero" "${LID_CHECK}"
check "the start record reports started daemons" test "$(record_field result)" = started
check "no ended process is left uncollected" bash -c "! grep -l '^State:.*Z' /proc/[0-9]*/status"
check "a software-emulated guest on the network default reaches the running state" start_emulated_guest network=default
check "the guest is removed" remove_guest

reportResults
