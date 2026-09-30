#!/bin/bash
# Scenario dind: docker-in-docker and firewall (presets npm, filterForward omitted). A nested
# container on a user-defined network, from an image imported from this container's own file system,
# reaches an allowed domain and is refused an unlisted one. Covers With docker-in-docker, Nested
# container filtered, Nested container on a user-defined network reaches an allowed domain, and
# Omitted filterForward.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "the forward chain is loaded" sh -c 'nft list table inet firewall | grep -q "hook forward"'
check "the nested Docker daemon runs" wait_for_docker
check "the nested image and network are set up" nested_setup
check "a nested container reaches registry.npmjs.org" nested_reachable https://registry.npmjs.org/
check "a nested container is refused github.com" nested_refused https://github.com/
check "the feature's table is still in place" sh -c 'nft list table inet firewall >/dev/null'

reportResults
