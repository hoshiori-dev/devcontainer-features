#!/usr/bin/env bash
# Scenario test_cached_metadata_offline_1 (scenarios.json): the scenario's Dockerfile writes a zypp configuration file
# that moves libzypp's caches, refreshes the repository metadata into them, and installs bc, and the container has no
# network. This script runs install.sh with ZYPP_CONF and refreshPolicy=never. Spec scenarios "Cached metadata is
# explicitly selected" (the parsed cache is rebuilt from the raw metadata, in the directories ZYPP_CONF names),
# "Missing cached metadata fails without refresh" (raw metadata that is not usable), and "Zypp configuration is
# unchanged".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly OWNED_CONF="/tmp/custom-zypp.conf"
readonly OWNED_CACHE="/tmp/owned-zypp"
readonly OWNED_METADATA="/tmp/owned-metadata"

# No name resolves, download.opensuse.org standing for any.
no_network() {
  ! getent hosts download.opensuse.org >/dev/null
}

# Prints the raw repository indexes in the directory ZYPP_CONF names.
owned_indexes() {
  local index
  for index in "${OWNED_METADATA}"/*/repodata/repomd.xml; do
    if [[ -s "${index}" ]]; then printf '%s\n' "${index}"; fi
  done
}

# The cache directory ZYPP_CONF names holds a parsed cache of a repository, @System being the installed packages.
owned_parsed_cache_exists() {
  local solv_file
  for solv_file in "${OWNED_CACHE}"/solv/*/solv; do
    if [[ -s "${solv_file}" && "${solv_file}" != */@System/solv ]]; then return 0; fi
  done
  echo "${OWNED_CACHE}/solv holds no parsed cache of a repository" >&2
  return 1
}

check "premise: the container has no network" no_network
check "premise: the image holds raw metadata in the directory ZYPP_CONF names" test -n "$(owned_indexes)"
configuration_before="$(zypp_configuration)"

rm -rf "${OWNED_CACHE}/solv"
run_install PACKAGES=bc ZYPP_CONF="${OWNED_CONF}" CLEANUP=none REFRESHPOLICY=never
check "refreshPolicy=never succeeds without a network and without a parsed cache" exited_with 0
check "the parsed cache is rebuilt in the directory ZYPP_CONF names" owned_parsed_cache_exists

while read -r index; do
  printf 'corrupt' >"${index}"
done < <(owned_indexes)
rm -rf "${OWNED_CACHE}/solv"
run_install PACKAGES=bc ZYPP_CONF="${OWNED_CONF}" CLEANUP=none REFRESHPOLICY=never
check "refreshPolicy=never fails when the raw metadata is corrupt" failed
check "the zypp configuration is unchanged" zypp_configuration_is "${configuration_before}"

reportResults
