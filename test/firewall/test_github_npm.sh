#!/usr/bin/env bash
# Scenario "test_github_npm": presets github,npm ("Presets combine"), and an address learned for a name that resolves
# inside a fetched GitHub range: raw.githubusercontent.com, whose addresses lie in the web range 185.199.108.0/22.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

# Whether the set of addresses learned for allowed domains holds one of raw.githubusercontent.com's four addresses.
raw_address_learned() {
  local learned address
  learned="$(nft list set inet firewall allowed_learned4)" || return 1
  for address in 185.199.108.133 185.199.109.133 185.199.110.133 185.199.111.133; do
    if [[ "${learned}" == *"${address}"* ]]; then return 0; fi
  done
  return 1
}

check "the current start is recorded as applied" record_current applied
# The number of ranges is GitHub's when the start fetched them, so the check matches any number.
check "with the github preset and defaultAction deny, the start fetched the GitHub ranges" \
  grep -q '^githubRanges=[0-9]' "${RECORD}"
check "the check exits zero" check_passes

# Presets combine
check "with presets github and npm, api.github.com is reachable" reachable https://api.github.com/
check "with presets github and npm, registry.npmjs.org is reachable" reachable https://registry.npmjs.org/

check "a connection to raw.githubusercontent.com, under the github preset's githubusercontent.com, succeeds" \
  reachable https://raw.githubusercontent.com/
# Deviation from shell-style.md (Tests): this label uses the words of the design's Goal "Learned addresses in their
# own sets", an invariant of the approach that no scenario of the spec states.
check "an address learned inside a fetched range is added to the learned set" raw_address_learned

reportResults
