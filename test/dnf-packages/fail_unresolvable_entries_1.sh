#!/usr/bin/env bash
# Scenario fail_unresolvable_entries_1 (scenarios.json): this script runs install.sh with lists whose entries are
# accepted but that dnf cannot satisfy from the image's repositories. Spec scenarios "Unknown package fails", "Names are
# matched in their letter case", "Architecture the repositories do not offer fails", "Unavailable pinned version fails",
# and "Conflict with an installed package fails".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The list $1 fails, file, which it also names, is not installed, and no installed package changed.
fails_without_change() {
  run_install PACKAGES="$1"
  failed && not_installed file && rpm_database_is "${database_before}"
}

database_before="$(rpm_database)"

check "file,package-that-does-not-exist-123456 (unknown package) fails and installs nothing" \
  fails_without_change "file,package-that-does-not-exist-123456"
check "file,Bc (another letter case than the offered bc) fails and installs nothing" fails_without_change "file,Bc"
check "file,bc.s390x (architecture the repositories do not offer) fails and installs nothing" \
  fails_without_change "file,bc.s390x"
check "file,bc-0.0.0-no-such-release (unavailable pinned version) fails and installs nothing" \
  fails_without_change "file,bc-0.0.0-no-such-release"

# A package the image ships and one that conflicts with it: Fedora ships coreutils, which conflicts with
# coreutils-single; the Enterprise Linux images ship curl-minimal, which conflicts with curl.
if rpm -q coreutils >/dev/null 2>&1; then
  shipped=coreutils
  conflicting=coreutils-single
else
  shipped=curl-minimal
  conflicting=curl
fi
check "premise: the image ships ${shipped}" installed "${shipped}"
run_install PACKAGES="${conflicting}"
check "${conflicting}, which conflicts with the installed ${shipped}, fails" failed
check "${shipped} stays installed" installed "${shipped}"
check "${conflicting} is not installed" not_installed "${conflicting}"
check "the conflict changed no installed package" rpm_database_is "${database_before}"

reportResults
