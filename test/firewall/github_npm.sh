#!/bin/bash
# Scenario github-npm: presets github,npm. Covers Presets combine, and a learned address inside a
# fetched GitHub range (raw.githubusercontent.com in the web ranges) joining its own set.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the GitHub ranges were fetched" sh -c "grep -q '^githubRanges=[0-9]' '$RECORD'"
check "the start check passes" check_passes
check "api.github.com reachable" reachable https://api.github.com/
check "registry.npmjs.org reachable" reachable https://registry.npmjs.org/
check "raw.githubusercontent.com reachable" reachable https://raw.githubusercontent.com/
learned_in_range() {
  as_root nft list set inet firewall allowed_learned4 | grep -q '185\.199\.1[01][0-9]\.133'
}
check "raw.githubusercontent.com's address learned inside a fetched range" learned_in_range

reportResults
