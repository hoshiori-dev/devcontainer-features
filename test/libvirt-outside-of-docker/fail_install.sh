#!/usr/bin/env bash
# Scenario "fail_install": the CLI installed libvirt-outside-of-docker on debian:13 with default options. The script
# runs the installer again with an invalid value of each option, with /etc/os-release naming an unsupported
# distribution, and with the libvirt-in-docker feature's share directory present: each run must fail with its reason
# before anything changes ("Unsupported distribution", "Installed after libvirt-in-docker").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

packages() {
  dpkg-query -W -f='${Package} ${Version}\n' | sha256sum
}

before="$(packages)"

status=0
output="$(run_installer VIRTINSTALL=maybe)" || status=$?
printf '%s\n' "${output}"
check "an invalid virtInstall fails the install" test "${status}" -ne 0
check "the failure names the accepted values of virtInstall" \
  grep -q 'option virtInstall is "maybe"; use true or false' <<<"${output}"

status=0
output="$(run_installer QEMUIMG=1)" || status=$?
printf '%s\n' "${output}"
check "an invalid qemuImg fails the install" test "${status}" -ne 0
check "the failure names the accepted values of qemuImg" \
  grep -q 'option qemuImg is "1"; use true or false' <<<"${output}"

work_dir="$(mktemp -d)"
cp /etc/os-release "${work_dir}/os-release"
printf '%s\n' 'ID=alpine' 'VERSION_ID=3.22' | as_root tee /etc/os-release >/dev/null
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root cp "${work_dir}/os-release" /etc/os-release
check "Unsupported distribution: the install fails" test "${status}" -ne 0
check "Unsupported distribution: the failure names the detected distribution" \
  grep -q 'unsupported distribution "alpine"' <<<"${output}"

as_root mkdir /usr/local/share/libvirt-in-docker
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root rmdir /usr/local/share/libvirt-in-docker
check "Installed after libvirt-in-docker: the install fails" test "${status}" -ne 0
check "Installed after libvirt-in-docker: the failure names both features as alternatives" \
  grep -q 'libvirt-outside-of-docker and libvirt-in-docker are alternatives' <<<"${output}"

check "the installed packages are unchanged by the failed runs" test "${before}" = "$(packages)"
check "the installed feature still works: the start check exits zero" check_reports_no_socket

rm -rf "${work_dir}"
reportResults
