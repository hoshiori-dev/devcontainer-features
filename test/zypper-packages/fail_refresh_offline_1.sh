#!/usr/bin/env bash
# Scenario fail_refresh_offline_1 (scenarios.json): the container has no network and the image holds no repository
# metadata, and this script runs install.sh with refreshPolicy=never and a list that needs metadata. Spec scenario
# "Missing cached metadata fails without refresh".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# zypper prints one of these texts when it fetches repository metadata.
attempted_no_download() {
  if output_matches 'fetch https?:|Downloading|Retrieving repository'; then
    echo "zypper tried to fetch metadata" >&2
    return 1
  fi
}

configuration_before="$(zypp_configuration)"

run_install PACKAGES=bc REFRESHPOLICY=never CLEANUP=packages
check "refreshPolicy=never without cached metadata exits with a non-zero status" failed
check "refreshPolicy=never without cached metadata names the missing metadata" \
  printed "refreshPolicy=never needs cached metadata"
check "refreshPolicy=never without cached metadata attempts no metadata download" attempted_no_download
check "refreshPolicy=never without cached metadata installs no bc" not_installed bc
check "refreshPolicy=never without cached metadata leaves the zypp configuration unchanged" \
  zypp_configuration_is "${configuration_before}"

reportResults
