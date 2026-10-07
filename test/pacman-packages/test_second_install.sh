#!/usr/bin/env bash
# Scenario test_second_install (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh several times in one container and asserts what each later run leaves. Spec scenarios "Listed package
# already up to date", "Conflict with an installed package fails", "Different list on the second install", "Same list
# on the second install", and "Constraint below the installed version on the second install".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints the install date the local database records for bc.
bc_install_date() {
  awk '/^%INSTALLDATE%$/ { getline; print }' /var/lib/pacman/local/bc-[0-9]*/desc
}

bc_install_date_is() {
  if [[ "$(bc_install_date)" != "$1" ]]; then
    echo "bc was reinstalled: its install date changed from $1 to $(bc_install_date)" >&2
    return 1
  fi
}

# The list $1 fails and leaves bc at the version $2.
fails_and_keeps_bc_at() {
  run_install PACKAGES="$1"
  failed && has_version bc "$2"
}

run_install PACKAGES=bc
check "the first installation of bc succeeds" exited_with 0
check "bc is installed" installed bc
bc_version="$(version_of bc)"
bc_date="$(bc_install_date)"
# A reinstall a second later would record another install date.
sleep 2
run_install PACKAGES=bc
check "bc listed again succeeds" exited_with 0
check "pacman skips bc, which is up to date" printed "is up to date -- skipping"
check "bc is left at ${bc_version}" has_version bc "${bc_version}"
check "bc is not reinstalled: its install date is unchanged" bc_install_date_is "${bc_date}"
download_sync_databases
check "premise: the installed bc ${bc_version} is the version the repositories offer" \
  test "$(offered_version bc)" = "${bc_version}"
remove_caches

run_install PACKAGES=vim
check "the installation of vim succeeds" exited_with 0
check "premise: tree is not installed" not_installed tree
run_install PACKAGES="tree,gvim"
check "a later list naming gvim, which conflicts with vim, fails" failed
check "pacman reports the conflict" printed "conflict"
check "vim stays installed" installed vim
check "gvim is not installed" not_installed gvim
check "tree, which the failed list also named, is not installed" not_installed tree

run_install PACKAGES=tree
check "a second installation with a different list succeeds" exited_with 0
check "bc, which the earlier list named, is still installed" installed bc
check "tree, which the later list named, is installed" installed tree

# jq and less, because every package of the lists above is installed by now.
check "premise: jq is not installed" not_installed jq
check "premise: less is not installed" not_installed less
run_install PACKAGES="jq,less"
check "the first installation of jq,less succeeds" exited_with 0
run_install PACKAGES="jq,less"
check "the second installation of the same list succeeds" exited_with 0
check "jq is installed" installed jq
check "less is installed" installed less

# A version of bc that existed: the one before the offered version, read from the Arch Linux Archive when the test runs.
download_sync_databases
bc_version="$(version_of bc)"
previous="$(previous_version bc)"
bc_previous="${previous%% *}"
remove_caches
check "a later list holding bc<${bc_version}, below the installed version, fails and leaves bc as it was" \
  fails_and_keeps_bc_at "bc<${bc_version}" "${bc_version}"
check "a later list holding bc=${bc_previous}, an older version, fails and leaves bc as it was" \
  fails_and_keeps_bc_at "bc=${bc_previous}" "${bc_version}"

reportResults
