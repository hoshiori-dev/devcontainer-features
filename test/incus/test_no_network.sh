#!/usr/bin/env bash
# Scenario "test_no_network": incus installed on debian:12 with default options, in a container started without a
# network. The daemon starts, the first initialization succeeds, and the start check passes ("Start without a
# network").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the container has no network interface but the loopback and those Incus created" \
  bash -c '! test -e /sys/class/net/eth0'
check "the start check exits zero" "${INCUS_CHECK}"
check "the start record reports a started daemon" test "$(record_field result)" = started
check "the start record reports the first initialization as done" \
  test "$(record_field initialization)" = "done: incus admin init --minimal"
check "the first initialization created a storage pool" has_storage_pool
check "the first initialization created a managed bridge" has_managed_network

reportResults
