#!/bin/bash
# Scenario domains: presets empty, allowedDomains githubusercontent.com. Covers Subdomain of an
# allowed domain, No preset, Address not obtained through the resolver, and GitHub preset not selected.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "nothing fetched without the github preset" record_is githubRanges "not fetched"
check "the start check passes" check_passes
check "raw.githubusercontent.com reachable through githubusercontent.com" reachable https://raw.githubusercontent.com/
unlearned_address_refused() {
  address=$(first_address github.com) || return 1
  echo "github.com at $address"
  refused --resolve "github.com:443:$address" https://github.com/
}
check "an address not learned for an allowed name is refused" unlearned_address_refused
check "github.com refused" refused https://github.com/
check "registry.npmjs.org refused" refused https://registry.npmjs.org/

reportResults
