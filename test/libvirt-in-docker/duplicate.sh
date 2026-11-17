#!/usr/bin/env bash
# Install-twice test: libvirt-in-docker is installed first with the non-default options the CLI picks (defaultNetwork
# false, swtpm true), then with the defaults. Option values arrive as DEFAULTNETWORK, SWTPM, and their __DEFAULT
# counterparts. The packages of the first install stay, each configuration block is present once, and the later
# install's defaultNetwork is in effect at the start.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the first install received defaultNetwork false and swtpm true, the second the defaults" \
  test "${DEFAULTNETWORK:-}:${SWTPM:-}:${DEFAULTNETWORK__DEFAULT:-}:${SWTPM__DEFAULT:-}" = false:true:true:false
check "swtpm, which the first install added, is still installed" swtpm_installed
check "/etc/libvirt/qemu.conf holds the feature's block once" block_once /etc/libvirt/qemu.conf
check "each daemon's configuration file holds the feature's block once" daemon_blocks_once
check "the start check exits zero" "${LID_CHECK}"
check "the later install's defaultNetwork is in effect: the network default is active" network_is_active
check "a software-emulated guest on the network default reaches the running state" start_emulated_guest network=default
check "the guest is removed" remove_guest

reportResults
