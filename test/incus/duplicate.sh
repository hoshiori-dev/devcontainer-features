#!/usr/bin/env bash
# Install-twice test: incus is installed first with the non-default options the CLI picks (channel lts-7.0, vm true,
# initialize none), then with the defaults. Option values arrive as CHANNEL, VM, INITIALIZE, and their __DEFAULT
# counterparts. The later install's options are in effect: the repository definition names only the stable channel,
# the stable version replaced the long-term support one, and a start initializes the daemon. The package incus, which
# the first install added, stays, and the remote user is in the incus-admin group once.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# The group incus-admin appears once among the remote user's groups, or the user is root.
in_admin_group_once() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then return 0; fi
  [[ "$(id -nG | tr ' ' '\n' | grep -c -x incus-admin)" == 1 ]]
}

check "the first install received lts-7.0, true, and none, the second the defaults" \
  test "${CHANNEL:-}:${VM:-}:${INITIALIZE:-}:${CHANNEL__DEFAULT:-}:${VM__DEFAULT:-}:${INITIALIZE__DEFAULT:-}" \
  = lts-7.0:true:none:stable:false:minimal
check "the repository definition names only the stable channel" sources_name_channel stable
check "the installed Incus is not of the 7.0 series, which the first install selected" \
  bash -c '! incus --version | grep -q "^7\.0\."'
check "incus-base is installed from the Zabbly repository" zabbly_package_installed incus-base
check "the package incus, which the first install added, is still installed" zabbly_package_installed incus
check "the start settings hold the later install's initialize" grep -q -x 'initialize=minimal' "${INCUS_SETTINGS}"
check "the start check exits zero" "${INCUS_CHECK}"
check "the later install's initialize is in effect: the daemon holds a storage pool" has_storage_pool
check "the remote user is in the incus-admin group once" in_admin_group_once
check "an instance starts and gets an address on the managed bridge" instance_starts_with_address
check "the instance is removed" remove_instance

reportResults
