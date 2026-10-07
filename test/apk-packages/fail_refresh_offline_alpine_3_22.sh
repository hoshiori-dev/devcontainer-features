#!/bin/sh
# Scenario fail_refresh_offline_alpine_3_22 (scenarios.json): the container has no network and the image holds no
# package index, and this script runs install.sh with refreshPolicy=never. Spec scenario "Missing cached metadata
# fails without refresh".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# apk 2 prints "fetch <URL>" for every index or package file it requests. apk 3 prints no such line when its output
# is not a terminal, so there the check rests on the container having no network.
attempted_no_download() {
  if output_matches 'fetch https?:|Downloading|Retrieving repository'; then
    echo "the run tried to fetch a file" >&2
    return 1
  fi
}

configuration_before="$(apk_configuration)"

run_install PACKAGES=tree REFRESHPOLICY=never CLEANUP=packages
check "refreshPolicy=never without a cached index exits with a non-zero status" install_failed
check "refreshPolicy=never without a cached index attempts no download" attempted_no_download
check "refreshPolicy=never without a cached index does not install tree" not_installed tree
check "refreshPolicy=never without a cached index leaves the apk configuration unchanged" \
  apk_configuration_is "${configuration_before}"

reportResults
