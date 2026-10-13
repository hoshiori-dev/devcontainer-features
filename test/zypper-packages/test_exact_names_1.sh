#!/usr/bin/env bash
# Scenario test_exact_names_1 (scenarios.json): this script runs install.sh with exactNames=true and with
# exactNames=false in one container. Spec scenarios "Exact names refuse a capability", "Exact names keep the qualified
# forms", and "Capability selects a providing package" for exactNames=false. awk is a capability gawk provides, and
# pkgconfig one that pkgconf-pkg-config provides; neither is the name of a package.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly QUALIFIED_PACKAGES=(tree file bc unzip zip)

# Prints the first edition the repositories offer of the package $1. Needs repository metadata.
offered_edition() {
  zypper --xmlout --non-interactive --no-refresh search --details --match-exact "$1" \
    | sed -n 's/.*<solvable[^>]*edition="\([^"]*\)".*/\1/p' \
    | sed -n 1p
}

# Prints the installed version of each of the packages installed with the qualified forms.
qualified_versions() {
  rpm -q "${QUALIFIED_PACKAGES[@]}"
}

# The script refreshes the metadata itself: it reads editions from it, which no fixed text could name for long.
zypper --non-interactive refresh
file_edition="$(offered_edition file)"
zip_edition="$(offered_edition zip)"
check "premise: the repositories offer an edition of file" test -n "${file_edition}"
check "premise: the repositories offer an edition of zip" test -n "${zip_edition}"
native="$(rpm --eval '%{_arch}')"
# The forms name, name=edition, name>=edition, name.architecture, and name followed by - and an edition.
qualified_entries="tree,file=${file_edition},bc>=1,unzip.${native},zip-${zip_edition}"
check "premise: pkgconf-pkg-config, which provides pkgconfig, is not installed" not_installed pkgconf-pkg-config
database_before="$(rpm_database)"

run_install PACKAGES=file,awk EXACTNAMES=true CLEANUP=none
check "with exactNames=true the list file,awk, a package and a capability, fails" failed
check "with exactNames=true and a capability in the list no file is installed" not_installed file
check "with exactNames=true no package is installed for the capability: the installed packages are unchanged" \
  rpm_database_is "${database_before}"

run_install PACKAGES=tree,pkgconfig EXACTNAMES=true CLEANUP=none
check "with exactNames=true the list tree,pkgconfig, a package and a capability, fails" failed
check "with exactNames=true pkgconf-pkg-config, which provides pkgconfig, is not installed" \
  not_installed pkgconf-pkg-config
check "with exactNames=true and the capability pkgconfig the installed packages are unchanged" \
  rpm_database_is "${database_before}"

run_install PACKAGES=gawk EXACTNAMES=true CLEANUP=none
check "with exactNames=true gawk, the name of the package that provides awk, succeeds" exited_with 0
check "gawk is installed" installed gawk

run_install PACKAGES="${qualified_entries}" EXACTNAMES=true CLEANUP=none
check "with exactNames=true ${qualified_entries} succeeds" exited_with 0
for package in "${QUALIFIED_PACKAGES[@]}"; do
  check "with exactNames=true ${package} is installed" installed "${package}"
done
exact_versions="$(qualified_versions)"
zypper --non-interactive remove "${QUALIFIED_PACKAGES[@]}"
run_install PACKAGES="${qualified_entries}" EXACTNAMES=false CLEANUP=none
check "with exactNames=false ${qualified_entries} succeeds" exited_with 0
check "each qualified entry installs with exactNames=true what it installs with exactNames=false" \
  test "$(qualified_versions)" = "${exact_versions}"

run_install PACKAGES=pkgconfig EXACTNAMES=false
check "with exactNames=false pkgconfig (a capability) installs" exited_with 0
check "pkgconf-pkg-config, which provides pkgconfig, is installed" installed pkgconf-pkg-config

reportResults
