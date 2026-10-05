#!/usr/bin/env bash
# Scenario "denied_domains": defaultAction allow, presets empty, allowedDomains raw.githubusercontent.com,
# deniedDomains githubusercontent.com,registry.npmjs.org, deniedCidrs 185.199.108.0/22, the range in which
# raw.githubusercontent.com resolves ("Allowed name inside a denied range", "Allowed subdomain of a denied domain",
# "Denied domain refused", "Unlisted destination let through").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

readonly RESOLVER_CONF="/run/firewall/dnsmasq.conf"
readonly ALLOWED_SETS="4#inet#firewall#allowed_learned4,6#inet#firewall#allowed_learned6"
readonly DENIED_SETS="4#inet#firewall#denied_learned4,6#inet#firewall#denied_learned6"

# Whether the resolver's configuration gives the allowed subdomain the allowed sets alone and the denied domain above
# it the denied sets alone.
one_verdict_per_domain() {
  grep -qxF "nftset=/raw.githubusercontent.com/${ALLOWED_SETS}" "${RESOLVER_CONF}" \
    && grep -qxF "nftset=/githubusercontent.com/${DENIED_SETS}" "${RESOLVER_CONF}"
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# Allowed name inside a denied range, Allowed subdomain of a denied domain
check "a connection to raw.githubusercontent.com, allowed under a denied domain and inside a denied range, succeeds" \
  reachable https://raw.githubusercontent.com/
# Deviation from shell-style.md (Tests): this label uses the words of the design's Goal "Learned addresses in their
# own sets", an invariant of the approach that no scenario of the spec states.
check "each domain entry gets one nftset line naming only its own verdict's sets" one_verdict_per_domain

# Denied domain refused
check "a lookup of registry.npmjs.org, a denied name, returns its addresses" resolves registry.npmjs.org
check "a connection to registry.npmjs.org, a denied name, fails with an error" refused https://registry.npmjs.org/

# Unlisted destination let through
check "a connection to github.com, a host that no option names, succeeds" reachable https://github.com/

reportResults
