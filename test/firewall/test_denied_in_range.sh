#!/usr/bin/env bash
# Scenario "test_denied_in_range": default options (the github preset) and deniedDomains raw.githubusercontent.com, a
# subdomain of the preset's githubusercontent.com whose addresses lie in a fetched GitHub range ("Denied subdomain of
# an allowed domain", "Denied name inside an allowed range").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# Denied subdomain of an allowed domain, Denied name inside an allowed range
check "a connection to raw.githubusercontent.com is refused although its addresses lie in a GitHub range" \
  refused https://raw.githubusercontent.com/
check "a connection to github.com, which the github preset allows and no entry denies, succeeds" \
  reachable https://github.com/

reportResults
