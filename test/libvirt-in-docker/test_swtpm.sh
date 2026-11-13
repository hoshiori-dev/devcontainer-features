#!/usr/bin/env bash
# Scenario "test_swtpm": libvirt-in-docker installed on debian:13 with swtpm true ("swtpm enabled"). The script then
# gives the image's qemu.conf a setting that the feature's block also sets and runs the installer again ("Earlier
# setting in the image", "Block replaced").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "swtpm and swtpm_setup are installed" swtpm_installed
check "the start check exits zero" "${LID_CHECK}"
check "the network default is active" network_is_active

printf 'user = "libvirt-qemu"\n' | as_root tee -a /etc/libvirt/qemu.conf >/dev/null
status=0
output="$(run_installer SWTPM=true)" || status=$?
printf '%s\n' "${output}"
check "Earlier setting in the image: the second install succeeds" test "${status}" -eq 0
check "Earlier setting in the image: the build log names the file and the setting" \
  grep -q '/etc/libvirt/qemu.conf sets user outside the feature.s block' <<<"${output}"
check "Earlier setting in the image: the feature's block stands first, once" \
  bash -c 'block_first /etc/libvirt/qemu.conf && block_once /etc/libvirt/qemu.conf'
check "Earlier setting in the image: the developer's line is kept" \
  as_root grep -q -x 'user = "libvirt-qemu"' /etc/libvirt/qemu.conf

reportResults
