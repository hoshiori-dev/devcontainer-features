#!/bin/sh
# Scenario fail_present_index_offline_alpine_3_24 (scenarios.json): the scenario's Dockerfile fills the image's
# configured cache with a fresh package index and the package files of file, and the container has no network. Spec
# scenario "Index present in the image is not used".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# /var/cache/apk holds a file whose name matches the pattern $1.
image_cache_holds() {
  for image_cache_holds_path in /var/cache/apk/$1; do
    if [ -f "${image_cache_holds_path}" ]; then return 0; fi
  done
  echo "/var/cache/apk holds no $1" >&2
  return 1
}

check "premise: the image's cache holds a package index" image_cache_holds 'APKINDEX*'
check "premise: the image's cache holds the package file of file" image_cache_holds 'file-*'
check "premise: a plain apk add would install file from that cache without the network" apk add --simulate file

state_before="$(apk_state)"
run_install PACKAGES=file
check "with a cached index and no reachable repository the feature fails" install_failed
check "the failure is the refresh's" printed "apk update failed"
check "file is not installed" not_installed file
check "the failed run changed nothing: apk's world, its installed database, and the caches" \
  apk_state_is "${state_before}"

reportResults
