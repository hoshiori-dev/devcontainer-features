#!/usr/bin/env bash
# Scenario fail_unresolvable_entries (scenarios.json): the feature is installed with an empty list, and this script then
# runs install.sh with lists whose entries are accepted but that the repositories cannot satisfy; each list also holds
# tree, which would install. Spec scenarios "Unsatisfied constraint fails", "Unknown package fails", "Entry is not
# matched as a regular expression", "Qualified entry outside the named repository fails", "Unknown repository fails",
# and "Repository name is matched exactly".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The list $1 fails and installs and upgrades nothing.
fails_without_change() {
  run_install PACKAGES="$1"
  failed && local_database_is "${database_before}"
}

# Read as a regular expression, b. matches the name of a package the repositories offer. Needs sync databases.
a_package_name_matches_b_dot() {
  local matched
  matched="$(pacman -Ssq '^b.$')" || matched=""
  printf 'as a regular expression, b. matches: %s\n' "${matched//$'\n'/ }"
  [[ -n "${matched}" ]]
}

# The sync databases offer the package $1 in the repository $2. Needs sync databases.
offered_by() {
  [[ "$(pacman -Si -- "$1" | sed -n 's/^Repository *: //p')" == "$2" ]]
}

# The version of bc the repositories offer when the test runs: no fixed version stays in a rolling release.
download_sync_databases
bc_version="$(offered_version bc)"
check "premise: extra offers bc, so core does not" offered_by bc extra
check "premise: the image configures the repositories core and extra, and no other" \
  test "$(pacman-conf --repo-list | tr '\n' ' ')" = "core extra "
remove_caches

database_before="$(local_database)"

check "premise: tree is not installed" not_installed tree
check "premise: bc is not installed" not_installed bc

check "tree,bc<${bc_version} (a constraint the offered version does not satisfy) fails and changes nothing" \
  fails_without_change "tree,bc<${bc_version}"

check "tree,pacman-packages-no-such-package (unknown package) fails and changes nothing" \
  fails_without_change "tree,pacman-packages-no-such-package"

check "tree,b. (not matched as a regular expression) fails and changes nothing" fails_without_change "tree,b."
download_sync_databases
check "premise: read as a regular expression, b. matches the name of an offered package" a_package_name_matches_b_dot
remove_caches

check "tree,core/bc (bc is offered by extra, not by the named core) fails and changes nothing" \
  fails_without_change "tree,core/bc"
check "pacman reports that it finds no target bc" printed "target not found: bc"
remove_caches

check "tree,pacman-packages-no-such-repository/bc (unknown repository) fails and changes nothing" \
  fails_without_change "tree,pacman-packages-no-such-repository/bc"
check "pacman's message names the repository" printed "database not found: pacman-packages-no-such-repository"
check "the package databases were synchronized before the unknown repository failed the run" has_sync_databases
remove_caches

check "tree,EXTRA/bc (a configured repository's name in another case) fails and changes nothing" \
  fails_without_change "tree,EXTRA/bc"
check "pacman reports EXTRA as an unknown repository" printed "database not found: EXTRA"

reportResults
