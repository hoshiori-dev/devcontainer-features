#!/usr/bin/env bash
# Scenario "test_container_command": libvirt-in-docker on an image built from debian:13 whose command, `sleep
# infinity`, stays the container's main process (overrideCommand false) and collects no ended processes ("Container
# command that collects nothing"). Without the init the feature requests, libvirtd would never answer here.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# Succeeds when no ended process stays uncollected: none is in state Z ("zombie") at one of five looks, a second
# apart. A process that has just ended may be seen once before the init collects it.
no_uncollected_process() {
  for _ in $(seq 1 5); do
    if ! grep -l '^State:.*Z' /proc/[0-9]*/status >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

check "the container's first process is the init the feature requests" container_has_init
check "the image's own command runs as a process" grep -q -x sleep /proc/[0-9]*/comm
check "the start check exits zero" "${LID_CHECK}"
check "the start record reports started daemons" test "$(record_field result)" = started
check "a software-emulated guest on the network default reaches the running state" start_emulated_guest network=default
check "the guest is removed" remove_guest
check "no ended process is left uncollected, the guest's QEMU included" no_uncollected_process

reportResults
