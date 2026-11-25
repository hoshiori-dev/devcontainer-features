#!/usr/bin/env bash
# Scenario "test_vm": incus installed on the Ubuntu 24.04 dev container image with vm true, for the remote user
# vscode. The package incus, which adds virtual machine support, is installed, and the daemon starts ("vm enabled").
# No virtual machine is started: the machines that run the tests may offer no /dev/kvm.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the package incus is installed from the Zabbly repository" zabbly_package_installed incus
check "incus-base is installed from the Zabbly repository" zabbly_package_installed incus-base
check "the start check exits zero" "${INCUS_CHECK}"
check "the remote user lists instances without sudo" incus list
check "the first initialization created a storage pool" has_storage_pool
check "the first initialization created a managed bridge" has_managed_network
check "the start record reports the first initialization as done" \
  test "$(record_field initialization)" = "done: incus admin init --minimal"

reportResults
