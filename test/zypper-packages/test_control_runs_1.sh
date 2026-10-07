#!/usr/bin/env bash
# Scenario test_control_runs_1 (scenarios.json): this script runs install.sh several times with different controls in
# one container. Spec scenarios "Only package files are cleaned", "Cached metadata is explicitly selected", "Later
# controls apply to the second installation", "Recommended packages are left out", "Optional dependency selection is
# enabled", "Current metadata is kept", and "Zypp configuration is unchanged"; and requirement "Installing the feature
# twice" for a later installRecommends=false, which uninstalls nothing. Its last run moves libzypp's caches with
# ZYPP_CONF, which test_cached_metadata_offline_1 then relies on without a network.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly SENTINEL="/var/cache/feature-unrelated/sentinel"
readonly OWNED_CONF="/tmp/custom-zypp.conf"
readonly OWNED_METADATA="/tmp/owned-metadata"

sentinel_kept() {
  [[ "$(<"${SENTINEL}")" == keep ]]
}

# Prints a digest of the raw repository metadata zypper has downloaded.
raw_metadata() {
  local file
  for file in /var/cache/zypp/raw/*/repodata/*; do
    if [[ -f "${file}" ]]; then sha256sum "${file}"; fi
  done | sort | sha256sum
}

raw_metadata_is() {
  if [[ "$(raw_metadata)" != "$1" ]]; then
    echo "the raw metadata under /var/cache/zypp/raw changed" >&2
    return 1
  fi
}

# The directory ZYPP_CONF names for raw metadata holds the index of a repository.
owned_metadata_holds_an_index() {
  local index
  for index in "${OWNED_METADATA}"/*/repodata/repomd.xml; do
    if [[ -s "${index}" ]]; then return 0; fi
  done
  echo "${OWNED_METADATA} holds no repository index" >&2
  return 1
}

# Leap's repository index service writes the repository definitions on zypper's first use; the digest of the
# configuration is taken after that.
zypper --non-interactive --no-refresh repos >/dev/null
configuration_before="$(zypp_configuration)"
mkdir -p "${SENTINEL%/*}"
echo keep >"${SENTINEL}"

run_install PACKAGES=bc CLEANUP=packages
check "bc installs with cleanup=packages" exited_with 0
check "bc is installed" installed bc
check "cleanup=packages leaves usable metadata" has_metadata
run_install PACKAGES=bc CLEANUP=none REFRESHPOLICY=never
check "a later run with refreshPolicy=never and cleanup=none succeeds from the kept metadata" exited_with 0
check "cleanup=none leaves the metadata in place" has_metadata
# A later default refresh and cleanup work after the earlier choice to keep the cache.
run_install PACKAGES=tree CLEANUP=all
check "a later run with the default refresh and cleanup=all succeeds" exited_with 0
check "bc, which the earlier list named, is still installed" installed bc
check "tree, which the later list named, is installed" installed tree
check "cleanup=all removes the metadata" no_metadata
check "no control value is written to the zypp configuration" zypp_configuration_is "${configuration_before}"
check "a cache directory the feature does not manage is untouched" sentinel_kept

# less recommends file, which nothing installed so far requires.
run_install PACKAGES=less CLEANUP=none
check "less installs with the default installRecommends" exited_with 0
check "by default the recommended package file is not installed" not_installed file
zypper --non-interactive remove less
run_install PACKAGES=less INSTALLRECOMMENDS=true CLEANUP=none
check "less installs with installRecommends=true" exited_with 0
check "with installRecommends=true the recommended package file is installed" installed file
run_install PACKAGES=less INSTALLRECOMMENDS=false
check "a later run with installRecommends=false succeeds" exited_with 0
check "a later installRecommends=false leaves the installed recommendation file in place" installed file

zypper --non-interactive refresh
raw_before="$(raw_metadata)"
check "premise: unzip is not installed" not_installed unzip
run_install PACKAGES=unzip CLEANUP=none
check "unzip installs with the default refresh over current metadata" exited_with 0
check "zypper reports the current metadata as up to date" printed "is up to date"
check "the default refresh replaces no current raw metadata" raw_metadata_is "${raw_before}"
check "unzip is installed" installed unzip

printf '[main]\ncachedir=/tmp/owned-zypp\nmetadatadir=%s\n' "${OWNED_METADATA}" >"${OWNED_CONF}"
run_install PACKAGES=zip ZYPP_CONF="${OWNED_CONF}" CLEANUP=none
check "zip installs with ZYPP_CONF naming other cache directories and cleanup=none" exited_with 0
check "the refresh wrote its metadata to the directory ZYPP_CONF names" owned_metadata_holds_an_index
check "the zypp configuration is still unchanged" zypp_configuration_is "${configuration_before}"

reportResults
