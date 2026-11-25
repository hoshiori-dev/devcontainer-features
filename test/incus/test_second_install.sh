#!/usr/bin/env bash
# Scenario "test_second_install": the CLI installed incus on debian:12 with default options. The script runs the
# installer again: with the same options, which changes nothing ("Same options twice"); with the channel lts-6.0,
# whose older version replaces the installed one ("Another channel"); with vm true and initialize none, and then with
# the defaults, after which the package incus stays and the later start settings hold ("Other start options");
# and with lts-6.0 once more, now that the package incus is installed, which follows to the older version.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# One digest over the repository definition, the key, and the start settings.
configuration() {
  cat "${INCUS_SOURCES}" "${INCUS_KEY}" "${INCUS_SETTINGS}" | sha256sum
}

# Runs the installer with the given options, shows its output, and returns its status.
install_again() {
  local output
  local status=0
  output="$(run_installer "$@")" || status=$?
  printf '%s\n' "${output}" | tail -n 25
  return "${status}"
}

# The packages incus, incus-base, and incus-client are installed in one and the same version.
packages_share_one_version() {
  [[ "$(dpkg-query -W -f='${Version}\n' incus incus-base incus-client | sort -u | wc -l)" == 1 ]]
}

before="$(configuration)"
version_before="$(incus --version)"
check "Same options twice: the second install succeeds" install_again
check "Same options twice: the repository definition, the key, and the start settings are unchanged" \
  test "$(configuration)" = "${before}"
check "Same options twice: the installed version is unchanged" test "$(incus --version)" = "${version_before}"

check "Another channel: the install with lts-6.0 succeeds" install_again CHANNEL=lts-6.0
check "Another channel: the repository definition names only lts-6.0" sources_name_channel lts-6.0
check "Another channel: incus --version reports a version of the 6.0 series" \
  bash -c 'incus --version | grep -q "^6\.0\."'
check "Another channel: incus-base is the Zabbly build" zabbly_package_installed incus-base

check "Other start options: the install with vm true and initialize none succeeds" \
  install_again VM=true INITIALIZE=none
check "Other start options: the repository definition names only stable again" sources_name_channel stable
check "Other start options: the package incus is installed" zabbly_package_installed incus
check "Other start options: the start settings hold initialize none" \
  grep -q -x 'initialize=none' "${INCUS_SETTINGS}"
check "Other start options: the install with defaults succeeds" install_again
check "Other start options: the package incus stays installed" zabbly_package_installed incus
check "Other start options: the start settings hold initialize minimal" \
  grep -q -x 'initialize=minimal' "${INCUS_SETTINGS}"
# The package incus is installed now, and it follows the others to the older channel instead of being removed.
check "Another channel, with the package incus installed: the install with lts-6.0 succeeds" \
  install_again CHANNEL=lts-6.0
check "Another channel, with the package incus installed: the package incus stays, as the Zabbly build" \
  zabbly_package_installed incus
check "Another channel, with the package incus installed: incus, incus-base, and incus-client share one version" \
  packages_share_one_version
check "Another channel, with the package incus installed: incus --version reports a version of the 6.0 series" \
  bash -c 'incus --version | grep -q "^6\.0\."'
check "the install with defaults succeeds once more" install_again
check "the repository definition, the key, and the start settings are as after the build" \
  test "$(configuration)" = "${before}"

reportResults
