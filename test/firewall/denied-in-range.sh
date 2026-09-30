#!/bin/bash
# Scenario denied-in-range: defaults (github preset) and deniedDomains raw.githubusercontent.com.
# Covers Denied subdomain of an allowed domain and Denied name inside an allowed range.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "raw.githubusercontent.com refused although inside a GitHub range" refused https://raw.githubusercontent.com/
check "github.com reachable" reachable https://github.com/

reportResults
