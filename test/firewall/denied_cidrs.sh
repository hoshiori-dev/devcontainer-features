#!/usr/bin/env bash
# Scenario "denied_cidrs": defaultAction allow, presets empty, allowedCidrs 185.199.109.133/32,185.199.110.0/24,
# deniedCidrs 185.199.108.0/22,185.199.110.0/24 ("Denied range under open egress", "Allowed address inside a denied
# range", "Same range allowed and denied", "Unlisted destination let through"). The addresses are
# raw.githubusercontent.com's, reached without a lookup.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# Denied range under open egress, Unlisted destination let through
check "a connection to 185.199.108.133, inside the denied range, fails with an error" raw_refused_at 185.199.108.133
check "a connection to github.com, a host outside the denied range that no option names, succeeds" \
  reachable https://github.com/

# Allowed address inside a denied range
check "a connection to 185.199.109.133, the allowed address inside the denied range, succeeds" raw_at 185.199.109.133
check "a connection to 185.199.111.133, another address of the denied range, fails with an error" \
  raw_refused_at 185.199.111.133

# Same range allowed and denied
check "a connection to 185.199.110.133, inside the range both allowed and denied, fails with an error" \
  raw_refused_at 185.199.110.133

reportResults
