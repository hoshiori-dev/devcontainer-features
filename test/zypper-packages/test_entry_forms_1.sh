#!/usr/bin/env bash
# Scenario test_entry_forms_1 (scenarios.json): this script runs install.sh several times in one container with the
# entry forms zypper accepts, and asserts what each later run leaves. Spec scenarios "Pinned version is installed",
# "Same list on the second install" (the package again, without its pin), "Native architecture qualifier is installed",
# "Different list on the second install", "Capability selects a providing package", "Range constraint is installed",
# "Name-version form selects that edition" (with the package already at that edition), and "Pin below the installed
# version on the second install".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints the editions the repositories offer of the package $1, one per line. Needs repository metadata.
offered_editions() {
  zypper --xmlout --non-interactive --no-refresh search --details --match-exact "$1" \
    | sed -n 's/.*<solvable[^>]*edition="\([^"]*\)".*/\1/p'
}

# Prints "<package> <oldest edition>" for the first of a few packages that the repositories offer in two editions, and
# nothing when they offer none of them in two. Chosen when the test runs, so that no fixed edition goes stale.
two_edition_package() {
  local candidate editions
  for candidate in file bc libfuse3-3 curl openssl-libs glibc; do
    editions="$(offered_editions "${candidate}" | sort -u -V)" || editions=""
    if [[ "${editions}" == *$'\n'* ]]; then
      echo "${candidate} ${editions%%$'\n'*}"
      return 0
    fi
  done
}

is_tumbleweed() {
  grep --quiet Tumbleweed /etc/os-release
}

# The script refreshes the metadata itself: it reads an edition of file from it.
zypper --non-interactive refresh
# An edition of file the repositories offer when the test runs: no fixed edition stays in them.
editions="$(offered_editions file)"
edition="${editions%%$'\n'*}"
check "premise: the repositories offer an edition of file" test -n "${edition}"

run_install PACKAGES="file=${edition}" CLEANUP=packages
check "file=${edition} (a pinned version) installs" exited_with 0
# rpm prints the version and release without the epoch and colon an edition may start with.
pinned_version="${edition#*:}"
check "file is installed at the pinned edition" has_version file "${pinned_version}"
run_install PACKAGES=file CLEANUP=packages
check "a later list naming file without a version succeeds" exited_with 0
check "file stays at the edition the repositories offer" has_version file "${pinned_version}"

native="$(rpm --eval '%{_arch}')"
run_install PACKAGES="bc.${native}" CLEANUP=packages
check "bc.${native} (the native architecture qualifier) installs" exited_with 0
check "file, which the earlier list named, is still installed" installed file
check "bc, which the later list named, is installed" installed bc

run_install PACKAGES=awk
check "awk (a capability) installs" exited_with 0
check "gawk, which provides awk, is installed" installed gawk

run_install PACKAGES="tree>=1"
check "tree>=1 (a range constraint) installs" exited_with 0
check "tree is installed" installed tree

run_install PACKAGES="file-${edition}"
check "file-${edition} (the name-version form) succeeds" exited_with 0

# The runs above removed the metadata (cleanup=all), and the script reads editions from it again.
zypper --non-interactive refresh
selection="$(two_edition_package)"
if [[ -z "${selection}" ]]; then
  # Tumbleweed publishes one edition of each package, so the check of a lower pin has no package to run with there.
  check "premise: only Tumbleweed may offer none of the candidate packages in two editions" is_tumbleweed
  echo "not run: the repositories offer no candidate package in two editions, so no lower pin is installed"
else
  read -r package older <<<"${selection}"
  older_version="${older#*:}"
  run_install PACKAGES="${package}"
  check "${package} without a version installs" exited_with 0
  installed_version="$(version_of "${package}")"
  check "premise: ${package} is at ${installed_version}, newer than the offered ${older}" \
    test "${installed_version}" != "${older_version}"
  run_install PACKAGES="${package}=${older}"
  check "a later list pinning ${package} to the older ${older} succeeds" exited_with 0
  check "${package} stays at ${installed_version}" has_version "${package}" "${installed_version}"
fi

reportResults
