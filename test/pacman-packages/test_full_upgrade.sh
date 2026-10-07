#!/usr/bin/env bash
# Scenario test_full_upgrade (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh in a container that holds outdated packages. Spec scenarios "Outdated installed packages are upgraded" and
# "Changed configuration file is kept on upgrade".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# nano ships /etc/nanorc as a backup file.
readonly CONFIGURATION_FILE="/etc/nanorc"

# Prints the installed packages for which the sync databases in the container offer a newer version.
outdated_packages() {
  # pacman -Qu exits 1 when it lists nothing.
  pacman -Qu || true
}

nothing_outdated() {
  local outdated
  outdated="$(outdated_packages)"
  if [[ -n "${outdated}" ]]; then
    printf 'still outdated after the feature ran:\n%s\n' "${outdated}" >&2
    return 1
  fi
}

# Installs the previous version of the package $1 from the Arch Linux Archive, so that the container holds an outdated
# package, and prints that version. Needs sync databases.
install_previous() {
  local previous
  previous="$(previous_version "$1")" || return
  pacman -U --noconfirm -- "${previous#* }" >/dev/null || return
  has_version "$1" "${previous%% *}" || return
  echo "${previous%% *}"
}

# Prints the md5 sum the local database records for the backup file $2 of the package $1, as the package ships it.
backup_sum() {
  awk -v file="${2#/}" '$1 == file && NF == 2 { print $2 }' /var/lib/pacman/local/"$1"-[0-9]*/files | head -n 1
}

# The file $1 has the sha256 digest $2.
has_content() {
  [[ "$(sha256sum <"$1")" == "$2" ]]
}

# The file $1 has the md5 sum $2.
is_package_copy() {
  [[ "$(md5sum <"$1")" == "$2 "* ]]
}

download_sync_databases
outdated_before="$(outdated_packages)"
if [[ -z "${outdated_before}" ]]; then
  # Nothing is outdated in this build of the image: make a small package outdated.
  tree_previous="$(install_previous tree)"
  outdated_before="tree ${tree_previous} -> $(offered_version tree)"
fi
remove_caches
printf 'outdated before the run:\n%s\n' "${outdated_before}"
# cleanup=none keeps the databases the run synchronized, so the check below compares the installed packages with what
# the run itself was offered; a later synchronization could list a package the mirror updated in between.
run_install PACKAGES=bc CLEANUP=none
check "bc installs in a container with outdated packages" exited_with 0
check "bc is installed" installed bc
check "premise: the run left the sync databases it downloaded" has_sync_databases
check "no installed package is older than the version the repositories offered the run" nothing_outdated

download_sync_databases
nano_current="$(offered_version nano)"
nano_previous="$(install_previous nano)"
shipped_before="$(backup_sum nano "${CONFIGURATION_FILE}")"
check "premise: nano ${nano_previous} records the backup file ${CONFIGURATION_FILE}" test -n "${shipped_before}"
echo '# changed by the pacman-packages tests' >>"${CONFIGURATION_FILE}"
changed="$(sha256sum <"${CONFIGURATION_FILE}")"
remove_caches
run_install PACKAGES=tree
check "tree installs with nano ${nano_previous} installed and ${nano_current} offered" exited_with 0
check "nano is upgraded to ${nano_current}" has_version nano "${nano_current}"
check "${CONFIGURATION_FILE} keeps its changed content" has_content "${CONFIGURATION_FILE}" "${changed}"
# pacman writes <file>.pacnew only when the new package's copy differs from the old package's.
shipped_now="$(backup_sum nano "${CONFIGURATION_FILE}")"
if [[ "${shipped_now}" != "${shipped_before}" ]]; then
  check "${CONFIGURATION_FILE}.pacnew is the copy nano ${nano_current} ships" \
    is_package_copy "${CONFIGURATION_FILE}.pacnew" "${shipped_now}"
else
  echo "${CONFIGURATION_FILE} is the same in nano ${nano_previous} and ${nano_current}, so no .pacnew is due"
fi

reportResults
