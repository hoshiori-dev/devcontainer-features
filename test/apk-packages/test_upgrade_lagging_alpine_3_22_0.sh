#!/bin/sh
# Scenario test_upgrade_lagging_alpine_3_22_0 (scenarios.json): the scenario's Dockerfile builds the first release of
# the Alpine branch, whose installed packages lag its repositories, and this script lists one of them. Spec scenarios
# "Listed package already installed stays at its version" and "Listed packages are upgraded on request".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# Prints a line "<name>-<installed version> <offered version>" for every installed package the repositories offer in
# a newer version.
lagging_packages() {
  apk --no-cache version -l '<' 2>/dev/null | awk '$2 == "<" { print $1, $3 }'
}

# The repositories still offer a newer version of the package: its line of lagging_packages is still $1.
still_lags() {
  lagging_packages | grep -Fqx -- "$1"
}

# The package and the versions are read when the test runs: which packages lag, and by how much, changes with every
# release of the branch.
first_lagging="$(lagging_packages | head -n 1)"
check "premise: an installed package lags the repositories" test -n "${first_lagging}"
installed_as="${first_lagging%% *}"
newer_version="${first_lagging#* }"
package="$(printf '%s\n' "${installed_as}" | sed 's/-[0-9][^-]*-r[0-9]*$//')"
version_before="$(installed_version "${package}")"
check "premise: ${package} is installed in a version" test -n "${version_before}"
check "premise: ${package} ${version_before} lags the offered ${newer_version}" \
  test "${version_before}" != "${newer_version}"

run_install PACKAGES="${package}"
check "the list ${package} installs with the default upgradePackages" exited_with 0
check "${package} stays at ${version_before}" installed_in_version "${package}" "${version_before}"
check "${package} is a line of apk's world" in_world "${package}"
check "the repositories still offer the newer ${package} ${newer_version}" still_lags "${first_lagging}"

run_install PACKAGES="${package}" UPGRADEPACKAGES=false
check "the list ${package} installs with upgradePackages=false" exited_with 0
check "upgradePackages=false leaves ${package} at ${version_before}" \
  installed_in_version "${package}" "${version_before}"
run_install PACKAGES="${package}" UPGRADEPACKAGES=true
check "the list ${package} installs with upgradePackages=true" exited_with 0
check "upgradePackages=true installs the offered ${package} ${newer_version}" \
  installed_in_version "${package}" "${newer_version}"
check "the upgraded ${package} is a line of apk's world" in_world "${package}"

reportResults
