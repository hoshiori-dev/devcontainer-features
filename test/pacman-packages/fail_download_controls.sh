#!/usr/bin/env bash
# Scenario fail_download_controls (scenarios.json): the feature is installed with an empty list, and this script then
# runs install.sh in a container it has prepared so that an explicit parallelDownloads cannot be confirmed, or so that
# the package database is locked. A stand-in before pacman on PATH records each call and then runs the real pacman.
# Spec scenarios "Image configuration that cannot be included fails closed", "Unconfirmed value fails closed", and
# "Held database lock fails the installation".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly CONFIGURATION="/etc/pacman.conf"
readonly CONFIGURATION_ASIDE="/etc/pacman.conf.aside"
readonly PACMAN_CONF="/usr/bin/pacman-conf"
readonly PACMAN_CONF_ASIDE="/usr/bin/pacman-conf.aside"
readonly LOCK_FILE="/var/lib/pacman/db.lck"

# Puts a stand-in named pacman-conf, whose body is $1, before the real one on the PATH of the runs below.
replace_pacman_conf() {
  printf '#!/bin/sh\n%s\n' "$1" >"${STAND_IN_DIR}/pacman-conf"
  chmod +x "${STAND_IN_DIR}/pacman-conf"
}

# The last run exited with status 1 and named parallelDownloads in an error message before it called pacman, so it
# synchronized, installed, and upgraded nothing, and it left no temporary file. Not the word anywhere in the output: the
# line install.sh logs before it writes the temporary configuration names the option in every run.
failed_closed() {
  exited_with 1 && printed_error "parallelDownloads" && pacman_was_called 0 && no_sync_databases \
    && temporary_files_are "${temporary_before}"
}

create_stand_in real
database_before="$(local_database)"
temporary_before="$(temporary_files)"
check "premise: tree is not installed" not_installed tree

mv "${CONFIGURATION}" "${CONFIGURATION_ASIDE}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with /etc/pacman.conf missing, parallelDownloads=3 fails closed" failed_closed
# A link to nothing: the file is there and cannot be read.
ln -s /nonexistent/pacman.conf "${CONFIGURATION}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with /etc/pacman.conf unreadable, parallelDownloads=3 fails closed" failed_closed
rm "${CONFIGURATION}"
mv "${CONFIGURATION_ASIDE}" "${CONFIGURATION}"

mv "${PACMAN_CONF}" "${PACMAN_CONF_ASIDE}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with pacman-conf missing, parallelDownloads=3 fails closed" failed_closed
mv "${PACMAN_CONF_ASIDE}" "${PACMAN_CONF}"

replace_pacman_conf "exit 1"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with a pacman-conf that fails, parallelDownloads=3 fails closed" failed_closed
image_value="$("${PACMAN_CONF}" ParallelDownloads)"
check "premise: the image does not set ParallelDownloads to 3 (it sets ${image_value})" test "${image_value}" != 3
replace_pacman_conf "echo ${image_value}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with a pacman-conf that reports the image's value, parallelDownloads=3 fails closed" failed_closed
replace_pacman_conf "exit 0"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "with a pacman-conf that reports no value, parallelDownloads=3 fails closed" failed_closed
rm "${STAND_IN_DIR}/pacman-conf"

check "no run that failed closed installed or upgraded a package" local_database_is "${database_before}"

# The lock of the package database is already held.
touch "${LOCK_FILE}"
for value in "" 3; do
  run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS="${value}"
  check "with the database lock held and parallelDownloads='${value}' the installation fails" failed
  check "the feature called pacman once and did not repeat the call" pacman_was_called 1
  check "pacman reports the lock" printed "unable to lock database"
  check "the lock file is still there" test -e "${LOCK_FILE}"
  check "nothing is installed or upgraded" local_database_is "${database_before}"
  check "no temporary file is left" temporary_files_are "${temporary_before}"
done
rm "${LOCK_FILE}"

run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "in the restored container tree installs with parallelDownloads=3" exited_with 0
check "tree is installed" installed tree

reportResults
