#!/usr/bin/env bash
# Scenario "domains": presets empty, allowedDomains githubusercontent.com ("Subdomain of an allowed domain", "No
# preset", "Address not obtained through the resolver", "GitHub preset not selected").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

# Whether a connection to github.com's address, without a lookup by curl, is refused. The address is the one a lookup
# returns when the test runs; github.com is no allowed name, so the resolver's answer allows nothing.
unlearned_address_refused() {
  local address
  address="$(first_address github.com)" || return 1
  printf 'github.com at %s\n' "${address}"
  refused --resolve "github.com:443:${address}" https://github.com/
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# GitHub preset not selected
check "without the github preset, the start fetches nothing" record_is githubRanges "not fetched"

# Subdomain of an allowed domain
check "a connection to raw.githubusercontent.com, a subdomain of the allowed domain, succeeds" \
  reachable https://raw.githubusercontent.com/

# Address not obtained through the resolver
check "a connection to an address the resolver has not returned for an allowed name is refused" \
  unlearned_address_refused

# No preset: only the one allowed domain is reachable.
check "a connection to github.com, which the allowed domain does not cover, is refused" refused https://github.com/
check "a connection to registry.npmjs.org, which the allowed domain does not cover, is refused" \
  refused https://registry.npmjs.org/

reportResults
