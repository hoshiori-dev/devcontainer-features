#!/bin/bash
# Scenario dind: docker-in-docker and firewall (presets npm, allowedCidrs 185.199.108.0/22,
# filterForward omitted). A nested container on a user-defined network, from an image imported from
# this container's own file system, reaches an address inside the allowed range (one of
# raw.githubusercontent.com's, without a lookup) and is refused a host no option allows. That a
# nested container reaches an allowed domain is not asserted: the feature does not guarantee it
# (Requirement: Forwarded traffic). Covers With docker-in-docker, Nested container filtered, Nested
# container reaches an allowed range, and Omitted filterForward.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the current start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "the forward chain is loaded" sh -c 'nft list table inet firewall | grep -q "hook forward"'
check "the nested Docker daemon runs" wait_for_docker
check "the nested image and network are set up" nested_setup
check "a nested container reaches 185.199.109.133 (allowed range)" nested_raw_at 185.199.109.133
check "a nested container is refused github.com" nested_refused https://github.com/
check "the feature's table is still in place" sh -c 'nft list table inet firewall >/dev/null'

reportResults
