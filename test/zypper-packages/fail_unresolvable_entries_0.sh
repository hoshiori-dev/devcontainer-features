#!/usr/bin/env bash
# Scenario fail_unresolvable_entries_0 (scenarios.json): this script runs install.sh with lists whose entries are
# accepted but that zypper cannot satisfy; each list but the last also holds a package that would install. Spec
# scenarios "Unknown package fails", "Name in another case fails", "Architecture the repositories do not offer fails",
# "Unavailable pinned version fails", "Unsatisfied range constraint fails", and "Conflict with an installed package
# fails".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The list "file,$1" fails, installs no file, and changes no installed package.
fails_without_partial_installation() {
  run_install PACKAGES="file,$1"
  failed && not_installed file && rpm_database_is "${database_before}"
}

database_before="$(rpm_database)"

check "file,package-that-does-not-exist-123456 (unknown package) fails and installs nothing" \
  fails_without_partial_installation "package-that-does-not-exist-123456"
check "file,Bc (name in another case) fails and installs nothing" fails_without_partial_installation "Bc"
check "file,bc.s390x (architecture the repositories do not offer) fails and installs nothing" \
  fails_without_partial_installation "bc.s390x"
check "file,bc=0.0.0-no-such-release (unavailable pinned version) fails and installs nothing" \
  fails_without_partial_installation "bc=0.0.0-no-such-release"
check "file,bc<0.0.0 (unsatisfied range constraint) fails and installs nothing" \
  fails_without_partial_installation "bc<0.0.0"

check "premise: coreutils, with which coreutils-single conflicts, is installed" installed coreutils
run_install PACKAGES=coreutils-single
check "coreutils-single, which conflicts with the installed coreutils, fails" failed
check "the conflict changes no installed package" rpm_database_is "${database_before}"

reportResults
