#!/usr/bin/env bash
# Scenario "test_allow_all": defaultAction allow, deniedCidrs the private ranges
# 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,100.64.0.0/10,fc00::/7,fe80::/10 ("Unlisted destination let
# through", "Unlisted traffic already let through", "Other DNS server refused", and "Denied range under open egress"
# by ruleset, since no test connects to a private address).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

# Whether the feature's table refuses each of the seven denied ranges.
private_ranges_refused() {
  local table refusals range
  table="$(table_listing)" || return 1
  refusals="$(grep 'goto refuse' <<<"${table}")" || return 1
  for range in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10; do
    if [[ "${refusals}" != *"${range}"* ]]; then
      printf 'no rule refuses %s\n' "${range}"
      return 1
    fi
  done
}

# Whether the last rule of the output chain, which decides what no entry matches, is a plain accept.
last_rule_accepts() {
  local chain last
  chain="$(nft list chain inet firewall output)" || return 1
  # The listing ends with the last rule and the closing braces of the chain and the table.
  last="$(awk '$1 != "}" { rule = $0 } END { print rule }' <<<"${chain}")"
  [[ "${last}" =~ ^[[:space:]]*accept$ ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# Unlisted traffic already let through
check "with the github preset and defaultAction allow, the start fetches nothing" \
  record_is githubRanges "not fetched"

# Unlisted destination let through
check "a connection to registry.npmjs.org, a host that no option names, succeeds" reachable https://registry.npmjs.org/
check "the rules accept what no entry matches" last_rule_accepts

# Other DNS server refused: over TCP, so that the refusal shows as a refused connection.
check "a DNS connection to 8.8.8.8, a public resolver that /etc/resolv.conf did not name, is refused" \
  refused http://8.8.8.8:53/

# Denied range under open egress
check "the rules refuse every range that deniedCidrs lists" private_ranges_refused

reportResults
