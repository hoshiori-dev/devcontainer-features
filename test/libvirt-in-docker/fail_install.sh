#!/usr/bin/env bash
# Scenario "fail_install": the CLI installed libvirt-in-docker on debian:13 with default options. The script runs the
# installer again with an invalid value of each option, with /etc/os-release naming an unsupported distribution, with
# a `uname` that names another architecture, and with the libvirt-outside-of-docker feature's share directory
# present: each run must fail with its reason before anything changes ("Unsupported distribution", "Installed after
# libvirt-outside-of-docker").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

packages() {
  dpkg-query -W -f='${Package} ${Version}\n' | sha256sum
}

before="$(packages)"
settings_before="$(cat /usr/local/share/libvirt-in-docker/settings)"

status=0
output="$(run_installer DEFAULTNETWORK=maybe)" || status=$?
printf '%s\n' "${output}"
check "an invalid defaultNetwork fails the install" test "${status}" -ne 0
check "the failure names the accepted values of defaultNetwork" \
  grep -q 'option defaultNetwork is "maybe"; use true or false' <<<"${output}"

status=0
output="$(run_installer SWTPM=yes)" || status=$?
printf '%s\n' "${output}"
check "an invalid swtpm fails the install" test "${status}" -ne 0
check "the failure names the accepted values of swtpm" grep -q 'option swtpm is "yes"; use true or false' <<<"${output}"

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

# Another architecture: `uname --machine` answered by a stand-in first on PATH.
mkdir "${work_dir}/bin"
printf '#!/bin/sh\necho riscv64\n' >"${work_dir}/bin/uname"
chmod +x "${work_dir}/bin/uname"
chmod a+rx "${work_dir}"
status=0
output="$(as_root env -i PATH="${work_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root \
  bash "$(dirname "$0")/_feature/install.sh" 2>&1)" || status=$?
printf '%s\n' "${output}"
check "an architecture other than amd64 and arm64 fails the install" test "${status}" -ne 0
check "the failure names the detected architecture" grep -q 'unsupported architecture "riscv64"' <<<"${output}"

as_root mkdir /usr/local/share/libvirt-outside-of-docker
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root rmdir /usr/local/share/libvirt-outside-of-docker
check "Installed after libvirt-outside-of-docker: the install fails" test "${status}" -ne 0
check "Installed after libvirt-outside-of-docker: the failure names both features as alternatives" \
  grep -q 'libvirt-in-docker and libvirt-outside-of-docker are alternatives' <<<"${output}"

check "the installed packages are unchanged by the failed runs" test "${before}" = "$(packages)"
check "the settings are unchanged by the failed runs" \
  test "${settings_before}" = "$(cat /usr/local/share/libvirt-in-docker/settings)"
check "the installed feature still works: the start check exits zero" "${LID_CHECK}"

rm -rf "${work_dir}"
reportResults
