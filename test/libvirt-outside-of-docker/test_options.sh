#!/usr/bin/env bash
# Scenario "test_options": libvirt-outside-of-docker installed on debian:13 with virtInstall false and qemuImg true
# ("virtInstall disabled", "qemuImg enabled").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "virsh is installed" virsh --version
check "virt-install is not installed" bash -c '! command -v virt-install'
check "qemu-img is installed" qemu-img --version
check "no libvirt daemon and no QEMU system emulator is installed" no_daemon_installed

reportResults
