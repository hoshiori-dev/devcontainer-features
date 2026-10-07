#!/usr/bin/env bash
# Scenario fail_refresh_and_signature (scenarios.json): the feature is installed with an empty list, and this script
# then runs install.sh in a container whose repositories or keyring it has broken, one way at a time. Spec scenarios
# "Failed refresh fails the feature" (one repository of several cannot be retrieved) and "Untrusted signature fails the
# install".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly MISSING_REPOSITORY="pacman-packages-missing"
readonly CONFIGURATION_BACKUP="/tmp/pacman.conf.backup"

names_the_signature() {
  printed "unknown trust" 2>/dev/null || printed "invalid or corrupted package (PGP signature)"
}

# The image's repositories synchronize; one more repository cannot be retrieved. Every repository has a database from
# an earlier synchronization, so a run that went on after the failure would install bc from them; without such
# databases pacman refuses the transaction by itself.
download_sync_databases
cp /etc/pacman.conf "${CONFIGURATION_BACKUP}"
cp /var/lib/pacman/sync/core.db "/var/lib/pacman/sync/${MISSING_REPOSITORY}.db"
# pacman expands $repo itself.
# shellcheck disable=SC2016
printf '\n[%s]\nServer = file:///nonexistent/$repo\n' "${MISSING_REPOSITORY}" >>/etc/pacman.conf
check "premise: the earlier databases offer bc" pacman -Si bc
database_before="$(local_database)"
run_install PACKAGES=bc
check "with one repository that cannot be retrieved the synchronization fails the feature" failed
check "pacman reports the failed synchronization" printed "failed to synchronize"
check "premise: the repository ${MISSING_REPOSITORY} is the one whose synchronization failed" \
  printed "'${MISSING_REPOSITORY}.db'"
check "with one repository that cannot be retrieved nothing is installed or upgraded" \
  local_database_is "${database_before}"
cp "${CONFIGURATION_BACKUP}" /etc/pacman.conf
remove_caches

# A freshly initialized keyring trusts none of the keys that sign the repositories' packages.
rm -rf /etc/pacman.d/gnupg
pacman-key --init >/dev/null 2>&1
database_before="$(local_database)"
run_install PACKAGES=bc
check "with a keyring that lacks the Arch Linux keys the feature fails" failed
check "the failure names the signature" names_the_signature
check "with a keyring that lacks the Arch Linux keys nothing is installed or upgraded" \
  local_database_is "${database_before}"

reportResults
