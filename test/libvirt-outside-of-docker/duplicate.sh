#!/usr/bin/env bash
# Install-twice test: libvirt-outside-of-docker is installed first with the non-default options the CLI picks
# (virtInstall false, qemuImg true), then with the defaults. Option values arrive as VIRTINSTALL, QEMUIMG, and their
# __DEFAULT counterparts. A package the first install added stays, and the second adds what it selects.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the first install received virtInstall false and qemuImg true, the second the defaults" \
  test "${VIRTINSTALL:-}:${QEMUIMG:-}:${VIRTINSTALL__DEFAULT:-}:${QEMUIMG__DEFAULT:-}" = false:true:true:false
check "virsh is installed" virsh --version
check "virt-install, which the second install selected, is installed" virt-install --version
check "qemu-img, which the first install added, is still installed" qemu-img --version
check "the settings file names one remote user" bash -c "test \"\$(grep -c '^remoteUser=' ${LOD_SETTINGS})\" = 1"
check "the start check exits zero and names the mount to add" check_reports_no_socket

reportResults
