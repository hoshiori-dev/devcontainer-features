#!/bin/bash
# Scenario allow-all: defaultAction allow and the private ranges denied. Covers Unlisted destination
# let through, Unlisted traffic already let through, Other DNS server refused, and Denied range under
# open egress (the private ranges' rejects in the ruleset).

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "nothing fetched with defaultAction allow" record_is githubRanges "not fetched"
check "the start check passes" check_passes
check "registry.npmjs.org reachable" reachable https://registry.npmjs.org/
check "TCP to 8.8.8.8 port 53 refused" refused http://8.8.8.8:53/
private_ranges_refused() {
  table_listing >/tmp/firewall-table.txt || return 1
  for range in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10; do
    grep "goto refuse" /tmp/firewall-table.txt | grep -q "$range" || { echo "missing $range"; return 1; }
  done
}
check "ruleset: the private ranges are refused" private_ranges_refused
last_rule_accepts() {
  as_root nft list chain inet firewall output | grep -v '^[[:space:]]*}' | tail -n 1 | grep -qx '[[:space:]]*accept'
}
check "ruleset: what no entry matches is accepted" last_rule_accepts

reportResults
