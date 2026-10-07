#!/usr/bin/env bash
# Scenario fail_unresolvable_entries_ubuntu (scenarios.json): this script runs install.sh with lists whose entries are
# accepted but that the package index cannot satisfy; each list also holds a package that would install. Spec scenarios
# "Unavailable pinned version fails", "Architecture the image has not enabled fails", "Unknown name ending in plus
# fails", "Unknown version ending in plus fails", "Unknown package fails", "Entry is not matched as a regular
# expression", "Virtual package with several providers fails", and "No version for the image's architecture".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The list $1 fails and changes no installed package.
fails_without_change() {
  run_install PACKAGES="$1"
  failed && dpkg_status_is "${status_before}"
}

no_foreign_architecture() {
  [[ -z "$(dpkg --print-foreign-architectures)" ]]
}

# The version $1 of bc is not in the index.
bc_has_no_version() {
  ! apt-cache show "bc=$1" 2>/dev/null | grep --fixed-strings --line-regexp --quiet "Version: $1"
}

several_providers_of_mail_transport_agent() {
  local providers
  providers="$(apt-cache showpkg mail-transport-agent | sed -n '/^Reverse Provides:/,$p' | tail -n +2 | grep -c .)"
  [[ "${providers}" -ge 2 ]]
}

# The script refreshes the index itself: it reads candidates from it, and every run below then uses it as it is.
as_root apt-get update -qq --error-on=any

status_before="$(dpkg_status)"
native="$(dpkg --print-architecture)"
# The candidate version of bc when the test runs, read from the index: no fixed version stays in the archive.
candidate="$(apt-cache policy bc | sed -n 's/^  Candidate: //p')"
# An architecture the image has not enabled, and a package the archives offer for another architecture only.
if [[ "${native}" == arm64 ]]; then
  foreign=s390x
  other_architecture_package=grub-pc
else
  foreign=s390x
  other_architecture_package=grub-efi-arm64
fi

check "file,bc=0.0.0-apt-packages-absent (unavailable pinned version) fails and changes nothing" \
  fails_without_change "file,bc=0.0.0-apt-packages-absent"

check "file,bc:${foreign} (architecture not enabled) fails and changes nothing" \
  fails_without_change "file,bc:${foreign}"
check "the feature enables no architecture" no_foreign_architecture

check "file,bc+ (unknown name ending in plus) fails and changes nothing" fails_without_change "file,bc+"

check "premise: the index holds no version ${candidate}+ of bc" bc_has_no_version "${candidate}+"
check "file,bc=${candidate}+ (unknown version ending in plus) fails and changes nothing" \
  fails_without_change "file,bc=${candidate}+"

check "bc,apt-packages-no-such-package (unknown package) fails and changes nothing" \
  fails_without_change "bc,apt-packages-no-such-package"

check "premise: read as a regular expression, zlib1g.dev matches the offered zlib1g-dev" apt-cache show zlib1g-dev
check "bc,zlib1g.dev (not matched as a regular expression) fails and changes nothing" \
  fails_without_change "bc,zlib1g.dev"

check "premise: mail-transport-agent has several providers" several_providers_of_mail_transport_agent
check "bc,mail-transport-agent (virtual package with several providers) fails and changes nothing" \
  fails_without_change "bc,mail-transport-agent"

check "bc,${other_architecture_package} (no version for ${native}) fails and changes nothing" \
  fails_without_change "bc,${other_architecture_package}"

reportResults
