#!/usr/bin/env bash
# Scenario test_entry_forms_0 (scenarios.json): this script runs install.sh several times in one container, with
# entries in the forms dnf matches. Spec scenarios "Pinned version is installed", "Different list on the second
# install", "Native architecture qualifier is installed", "Capability selects a providing package", and "Program name
# selects a package where dnf matches program names".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints the first edition ("<version>-<release>", after "<epoch>:" where the package has one) that the repositories
# list for the package $1.
first_offered_edition() {
  local listing
  listing="$(dnf list --showduplicates "$1")"
  awk -v prefix="$1." 'index($1, prefix) == 1 { print $2; exit }' <<<"${listing}"
}

dnf_matches_program_names() {
  local version
  version="$(dnf --version)"
  [[ "${version}" == *dnf5* ]]
}

# An edition of file the repositories offer when the test runs: no fixed version stays in them.
edition="$(first_offered_edition file)"
check "premise: the repositories offer an edition of file" test -n "${edition}"
run_install PACKAGES="file-${edition}" CLEANUP=packages
check "file-${edition} (a pinned version) installs" exited_with 0
check "file is installed at the pinned version ${edition#*:}" has_version file "${edition#*:}"
run_install PACKAGES=file CLEANUP=packages
check "a later list naming file without a version succeeds" exited_with 0
check "file stays at ${edition#*:}" has_version file "${edition#*:}"

architecture="$(rpm --eval '%{_arch}')"
run_install PACKAGES="bc.${architecture}" CLEANUP=packages
check "bc.${architecture} (the native architecture) installs as a different list" exited_with 0
check "file, which the earlier lists named, is still installed" installed file
check "bc is installed for ${architecture}" installed "bc.${architecture}"

run_install PACKAGES=libz.so.1
check "libz.so.1 (a capability no package is named after) installs" exited_with 0
check "a package that provides libz.so.1 is installed" rpm -q --whatprovides libz.so.1

# dig is a program of bind-utils; no package is named dig or provides it as a capability.
check "premise: bind-utils is not installed" not_installed bind-utils
run_install PACKAGES=dig
if dnf_matches_program_names; then
  check "dig (a program name) installs where dnf matches program names" exited_with 0
  check "bind-utils, which ships dig, is installed" installed bind-utils
else
  check "dig (a program name) fails where dnf does not match program names" failed
  check "bind-utils, which ships dig, is not installed" not_installed bind-utils
fi

reportResults
