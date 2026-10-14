#!/usr/bin/env bash
# Scenario test_parallel_downloads (scenarios.json): the feature is installed with an empty list, and this script then
# runs install.sh with and without parallelDownloads, with a stand-in before pacman on PATH that records each call and
# then runs the real pacman. Spec scenarios "Native parallel downloads are inherited", "Explicit parallel downloads
# reach pacman", "Temporary configuration is removed", "Parallel downloads apply under every cleanup value", "Parallel
# downloads apply to repository-qualified entries", "Explicit parallel downloads keep the image configuration" (the
# resolved configuration), "Download controls do not persist to the second install", and "Build environment proxy
# reaches pacman unchanged".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# A proxy address nothing listens on; the runs that receive it call a stand-in that downloads nothing.
readonly PROXY="http://127.0.0.1:9"
readonly PROXY_VARIABLES=(
  "http_proxy=${PROXY}" "https_proxy=${PROXY}" "HTTPS_PROXY=${PROXY}" "ALL_PROXY=${PROXY}" "no_proxy=localhost"
)

# The configuration file of the last run's pacman call held exactly the inclusion of /etc/pacman.conf and the
# ParallelDownloads value $1, each under an [options] header.
configuration_held_only() {
  local expected
  expected="$(printf '[options]\nInclude = /etc/pacman.conf\n[options]\nParallelDownloads = %s\n' "$1")"
  if [[ "$(<"${RECORD_DIR}/configuration")" != "${expected}" ]]; then
    echo "the temporary configuration held:" >&2
    cat "${RECORD_DIR}/configuration" >&2
    return 1
  fi
}

# The configuration file the last run's pacman call named lay directly under /tmp and no longer exists.
recorded_configuration_is_removed() {
  local path
  path="$(recorded_configuration_path)"
  if [[ "${path}" != /tmp/pacman-packages.* || "${path#/tmp/}" == */* || -e "${path}" ]]; then
    echo "the temporary configuration ${path} is not a removed file directly under /tmp" >&2
    return 1
  fi
}

# The last run's pacman call named no configuration file.
pacman_received_no_configuration() {
  if grep -q -- '--config' "${RECORD_DIR}/arguments"; then
    echo "pacman received --config" >&2
    return 1
  fi
}

# The sync databases offer the package $1 in the repository $2. Needs sync databases.
offered_by() {
  [[ "$(pacman -Si -- "$1" | sed -n 's/^Repository *: //p')" == "$2" ]]
}

no_package_files() {
  if [[ -n "$(find /var/cache/pacman/pkg -mindepth 1 -print -quit)" ]]; then
    echo "/var/cache/pacman/pkg holds a file" >&2
    return 1
  fi
}

has_package_files() {
  [[ -n "$(find /var/cache/pacman/pkg -name '*.pkg.tar.*' -print -quit)" ]]
}

# The environment of the last run's pacman call holds exactly the proxy variables given, with their values.
pacman_received_proxy_variables() {
  local received
  received="$(grep -i proxy "${RECORD_DIR}/environment" | LC_ALL=C sort)" || received=""
  if [[ "${received}" != "$(printf '%s\n' "$@" | LC_ALL=C sort)" ]]; then
    printf 'pacman received the proxy variables:\n%s\n' "${received}" >&2
    return 1
  fi
}

create_stand_in real
image_configuration="$(pacman-conf)"
image_repositories="$(pacman-conf --repo-list)"
image_value="$(pacman-conf ParallelDownloads)"
configuration_before="$(repository_configuration)"
temporary_before="$(temporary_files)"
# The values the runs below set must differ from the image's, so that a run that ignored the option would show.
check "premise: the image does not set ParallelDownloads to 3 (it sets ${image_value})" test "${image_value}" != 3
check "premise: the image does not set ParallelDownloads to 7" test "${image_value}" != 7

# which, because the image ships none of the packages this script lists.
check "premise: which is not installed" not_installed which
run_install_with_stand_in PACKAGES=which
check "which installs without parallelDownloads" exited_with 0
check "which is installed" installed which
check "the feature calls pacman once" pacman_was_called 1
check "without parallelDownloads the pacman call names no configuration file and has the arguments of version 1.0.1" \
  pacman_received "${PACMAN_ARGUMENTS[@]}" which
check "without parallelDownloads the feature creates no file under /tmp" temporary_files_are "${temporary_before}"

check "premise: bc is not installed" not_installed bc
check "premise: tree is not installed" not_installed tree
run_install_with_stand_in PACKAGES="extra/bc,tree" PARALLELDOWNLOADS=3
check "extra/bc,tree installs with parallelDownloads=3" exited_with 0
check "the feature calls pacman once for the qualified and the unqualified entry" pacman_was_called 1
check "the pacman call adds only --config and its file to the arguments of version 1.0.1" \
  pacman_received --config "$(recorded_configuration_path)" "${PACMAN_ARGUMENTS[@]}" extra/bc tree
check "the configuration pacman resolves for the call has ParallelDownloads = 3" resolved_parallel_downloads 3
check "the temporary configuration holds only the inclusion of /etc/pacman.conf and ParallelDownloads = 3" \
  configuration_held_only 3
check "the temporary configuration is readable by root only" test "$(<"${RECORD_DIR}/configuration_mode")" = "600 root"
check "the resolved configuration equals the image's in everything but ParallelDownloads" \
  resolved_configuration_equals_except_parallel_downloads "${image_configuration}"
check "the resolved configuration has the image's repositories in their order" \
  test "$(<"${RECORD_DIR}/repositories")" = "${image_repositories}"
check "bc is installed" installed bc
check "tree is installed" installed tree
check "the temporary configuration is removed after the installation succeeded" recorded_configuration_is_removed
check "nothing is left under /tmp" temporary_files_are "${temporary_before}"
check "cleanup=all removes the package files with parallelDownloads=3" no_package_files
check "cleanup=all removes the sync databases with parallelDownloads=3" no_sync_databases
check "/etc/pacman.conf and the mirror list are unchanged" repository_configuration_is "${configuration_before}"
download_sync_databases
check "the repository extra, which the entry extra/bc names, is the one that offers bc" offered_by bc extra
remove_caches

check "premise: jq is not installed" not_installed jq
run_install_with_stand_in PACKAGES=jq PARALLELDOWNLOADS=3 CLEANUP=packages
check "jq installs with parallelDownloads=3 and cleanup=packages" exited_with 0
check "the configuration pacman resolves for that call has ParallelDownloads = 3" resolved_parallel_downloads 3
check "cleanup=packages removes the package files" no_package_files
check "cleanup=packages keeps the sync databases" has_sync_databases
check "the temporary configuration is removed under cleanup=packages" temporary_files_are "${temporary_before}"

check "premise: less is not installed" not_installed less
run_install_with_stand_in PACKAGES=less PARALLELDOWNLOADS=3 CLEANUP=none
check "less installs with parallelDownloads=3 and cleanup=none" exited_with 0
check "the configuration pacman resolves for that call has ParallelDownloads = 3" resolved_parallel_downloads 3
check "cleanup=none keeps the package files" has_package_files
check "cleanup=none keeps the sync databases" has_sync_databases
check "the temporary configuration is removed under cleanup=none" temporary_files_are "${temporary_before}"
remove_caches

run_install_with_stand_in PACKAGES=pacman-packages-no-such-package PARALLELDOWNLOADS=3
check "an unknown package fails the installation in pacman with parallelDownloads=3" failed
check "pacman was called for it" pacman_was_called 1
check "pacman reports the unknown package" printed "target not found: pacman-packages-no-such-package"
check "the temporary configuration is removed after the installation failed in pacman" \
  recorded_configuration_is_removed
check "nothing is left under /tmp after the failed installation" temporary_files_are "${temporary_before}"
remove_caches

# The installation of extra/bc,tree above set parallelDownloads=3 and held a qualified entry.
check "premise: nano is not installed" not_installed nano
run_install_with_stand_in PACKAGES=nano
check "a later installation without parallelDownloads succeeds" exited_with 0
check "its pacman call names no configuration file, so the image's setting applies" pacman_received_no_configuration
check "it finds no temporary configuration of the earlier installation" temporary_files_are "${temporary_before}"
check "bc, installed earlier for the entry extra/bc, is still installed" installed bc
check "premise: rsync is not installed" not_installed rsync
run_install_with_stand_in PACKAGES=rsync PARALLELDOWNLOADS=7
check "a later installation with parallelDownloads=7 succeeds" exited_with 0
check "its pacman call resolves ParallelDownloads as 7, its own value" resolved_parallel_downloads 7
check "/etc/pacman.conf and the mirror list are unchanged after every run" \
  repository_configuration_is "${configuration_before}"

# From here on pacman is a stand-in that records its call and downloads nothing.
create_stand_in only
run_install_with_stand_in PACKAGES=tree "${PROXY_VARIABLES[@]}"
check "a run with proxy variables in its environment calls pacman" pacman_was_called 1
check "pacman receives those proxy variables with the same values and no other" \
  pacman_received_proxy_variables "${PROXY_VARIABLES[@]}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3 "${PROXY_VARIABLES[@]}"
check "with parallelDownloads=3 pacman receives those proxy variables with the same values and no other" \
  pacman_received_proxy_variables "${PROXY_VARIABLES[@]}"
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=3
check "without proxy variables in the environment pacman receives none" pacman_received_proxy_variables

reportResults
