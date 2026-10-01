#!/bin/bash
# Scenario cidrs: presets empty, allowedCidrs 185.199.108.0/22,2606:50c0::/32, deniedCidrs
# 185.199.108.133/32. Covers IPv4 and IPv6 ranges (IPv4 by connection, IPv6 by ruleset) and Denied
# range inside an allowed range. Addresses are raw.githubusercontent.com's, reached without a lookup.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "185.199.109.133 reachable (allowed range)" raw_at 185.199.109.133
check "185.199.110.133 reachable (allowed range)" raw_at 185.199.110.133
check "185.199.108.133 refused (denied range inside the allowed range)" raw_refused_at 185.199.108.133
check "github.com refused (outside both ranges)" refused https://github.com/
ipv6_range_allowed() {
  table_listing | grep -q 'ip6 daddr 2606:50c0::/32 accept'
}
check "ruleset: the IPv6 range is allowed" ipv6_range_allowed

reportResults
