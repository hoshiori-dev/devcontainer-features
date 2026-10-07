#!/usr/bin/env bash
# Scenario test_control_runs (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh several times with different controls in one container. Spec scenarios "Only package files are cleaned",
# "Later controls apply to the second installation", and "Custom cache paths are outside the cleanup bound".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly SENTINEL="/var/cache/feature-unrelated/sentinel"
readonly CUSTOM_CACHE="/tmp/custom-cache"
readonly CUSTOM_DATABASE="/tmp/custom-db"

sentinel_kept() {
  [[ "$(<"${SENTINEL}")" == keep ]]
}

no_sync_database_files() {
  if [[ -n "$(find /var/lib/pacman/sync -name '*.db' -print -quit)" ]]; then
    echo "/var/lib/pacman/sync holds a sync database" >&2
    return 1
  fi
}

# The directory $1 holds a file whose name matches $2.
holds() {
  [[ -n "$(find "$1" -name "$2" -print -quit)" ]]
}

configuration_before="$(repository_configuration)"
mkdir -p "${SENTINEL%/*}"
echo keep >"${SENTINEL}"

run_install PACKAGES=tree CLEANUP=packages
check "tree installs with cleanup=packages" exited_with 0
check "tree is installed" installed tree
check "cleanup=packages leaves usable metadata" has_sync_databases
run_install PACKAGES=tree CLEANUP=none
check "a later run with cleanup=none succeeds" exited_with 0
check "cleanup=none leaves the metadata in place" has_sync_databases
# A later default cleanup works after the earlier choice to keep the cache. which, because the image ships file, the
# other package the proposals name.
check "premise: which is not installed" not_installed which
run_install PACKAGES=which CLEANUP=all
check "a later run with another list and cleanup=all succeeds" exited_with 0
check "tree, which the earlier list named, is still installed" installed tree
check "which, which the later list named, is installed" installed which
check "cleanup=all removes the metadata" no_sync_database_files
check "no control value is written to the repository configuration" \
  repository_configuration_is "${configuration_before}"
check "a cache directory the feature does not manage is untouched" sentinel_kept

# The image moves pacman's package cache and database; cleanup stays within the default directories. bc, because the
# run must download a package and tree is installed by now.
mkdir -p "${CUSTOM_CACHE}" "${CUSTOM_DATABASE}"
cp -a /var/lib/pacman/local "${CUSTOM_DATABASE}/"
sed -i "/^\[options\]/a CacheDir = ${CUSTOM_CACHE}\nDBPath = ${CUSTOM_DATABASE}" /etc/pacman.conf
configuration_before="$(repository_configuration)"
check "premise: bc is not installed" not_installed bc
run_install PACKAGES=bc CLEANUP=all
check "bc installs with a custom CacheDir and DBPath and cleanup=all" exited_with 0
check "cleanup=all leaves the package files in the custom CacheDir" holds "${CUSTOM_CACHE}" '*.pkg.tar.*'
check "cleanup=all leaves the sync databases under the custom DBPath" holds "${CUSTOM_DATABASE}/sync" '*.db'
check "the configuration of the custom paths is unchanged" repository_configuration_is "${configuration_before}"

reportResults
