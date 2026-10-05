#!/usr/bin/env bash
# Scenario "cidrs": presets empty, allowedCidrs 185.199.108.0/22,2606:50c0::/32, deniedCidrs 185.199.108.133/32
# ("IPv4 and IPv6 ranges", IPv4 by connection and IPv6 by ruleset, since the harness has no IPv6; "Denied range inside
# an allowed range"). The addresses are raw.githubusercontent.com's, reached without a lookup.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

ipv6_range_accepted() {
  local table
  table="$(table_listing)" || return 1
  [[ "${table}" == *"ip6 daddr 2606:50c0::/32 accept"* ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# IPv4 and IPv6 ranges
check "a connection to 185.199.109.133, inside the allowed IPv4 range, succeeds" raw_at 185.199.109.133
check "a connection to 185.199.110.133, inside the allowed IPv4 range, succeeds" raw_at 185.199.110.133
check "github.com, an address outside both ranges, stays refused" refused https://github.com/
check "the rules accept the allowed IPv6 range 2606:50c0::/32" ipv6_range_accepted

# Denied range inside an allowed range
check "a connection to 185.199.108.133, the denied range inside the allowed range, fails with an error" \
  raw_refused_at 185.199.108.133

reportResults
