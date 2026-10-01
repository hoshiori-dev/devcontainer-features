#!/bin/bash
# Scenario dind-no-forward: docker-in-docker and firewall (presets npm, filterForward false). A
# nested container reaches github.com, which no option allows, while the dev container itself is
# refused it. Covers Forwarded traffic not filtered.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "no forward chain is loaded" sh -c '! nft list table inet firewall | grep -q "hook forward"'
check "the nested Docker daemon runs" wait_for_docker
check "the nested image and network are set up" nested_setup
check "a nested container reaches github.com" nested_reachable https://github.com/
check "the dev container itself is refused github.com" refused https://github.com/

reportResults
