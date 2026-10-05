#!/bin/bash
# Scenario denied-domains: defaultAction allow, presets empty, allowedDomains
# raw.githubusercontent.com, deniedDomains githubusercontent.com,registry.npmjs.org, deniedCidrs
# 185.199.108.0/22. Covers Allowed name inside a denied range, Allowed subdomain of a denied domain,
# Denied domain refused, and Unlisted destination let through.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "raw.githubusercontent.com reachable" reachable https://raw.githubusercontent.com/
check "registry.npmjs.org resolves" resolves registry.npmjs.org
check "registry.npmjs.org refused" refused https://registry.npmjs.org/
check "github.com reachable" reachable https://github.com/
resolver_lines() {
  grep -qx 'nftset=/raw.githubusercontent.com/4#inet#firewall#allowed_learned4,6#inet#firewall#allowed_learned6' \
    /run/firewall/dnsmasq.conf \
    && grep -qx 'nftset=/githubusercontent.com/4#inet#firewall#denied_learned4,6#inet#firewall#denied_learned6' \
      /run/firewall/dnsmasq.conf
}
check "the resolver learns each domain into its own verdict's sets" resolver_lines

reportResults
