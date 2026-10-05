#!/bin/bash
# Scenario denied-cidrs: defaultAction allow, presets empty, allowedCidrs
# 185.199.109.133/32,185.199.110.0/24, deniedCidrs 185.199.108.0/22,185.199.110.0/24. Covers Denied
# range under open egress, Allowed address inside a denied range, Same range allowed and denied, and
# Unlisted destination let through. Addresses are raw.githubusercontent.com's, reached without a lookup.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "185.199.108.133 refused (denied range)" raw_refused_at 185.199.108.133
check "185.199.111.133 refused (rest of the denied range)" raw_refused_at 185.199.111.133
check "185.199.109.133 reachable (allowed address inside the denied range)" raw_at 185.199.109.133
check "185.199.110.133 refused (same range allowed and denied)" raw_refused_at 185.199.110.133
check "github.com reachable (outside every entry)" reachable https://github.com/

reportResults
