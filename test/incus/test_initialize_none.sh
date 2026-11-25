#!/usr/bin/env bash
# Scenario "test_initialize_none": incus installed on ubuntu:22.04 with initialize none. The daemon answers and
# holds no storage pool and no managed network ("initialize none"); the developer's preseed, applied twice, leaves
# the daemon as after the first time ("Preseed applied twice"); and a later run of the start script changes none of
# it ("Developer's own initialization").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# Succeeds when the command given fails.
not() {
  ! "$@"
}

# The storage pools and the networks of the daemon, as one text.
pools_and_networks() {
  incus storage list --format csv --columns nD
  incus network list --format csv --columns ntm
}

check "the start check exits zero" "${INCUS_CHECK}"
check "the start record says no initialization was requested" \
  test "$(record_field initialization)" = "not requested (initialize is none)"
check "the daemon holds no storage pool" not has_storage_pool
check "the daemon holds no managed network" not has_managed_network

preseed="$(mktemp)"
cat >"${preseed}" <<'PRESEED'
networks:
  - name: devbr0
    type: bridge
    config:
      ipv4.address: 10.77.0.1/24
      ipv4.nat: "true"
      ipv6.address: none
storage_pools:
  - name: data
    driver: dir
profiles:
  - name: default
    devices:
      root:
        path: /
        pool: data
        type: disk
      eth0:
        name: eth0
        network: devbr0
        type: nic
PRESEED

check "the preseed is applied" bash -c "incus admin init --preseed <'${preseed}'"
after_first="$(pools_and_networks)"
printf '%s\n' "${after_first}"
check "the daemon holds the pool and the bridge the preseed describes" \
  bash -c 'incus storage show data >/dev/null && incus network show devbr0 >/dev/null'
check "the preseed is applied a second time without error" bash -c "incus admin init --preseed <'${preseed}'"
check "the pools and networks are as after the first time" test "$(pools_and_networks)" = "${after_first}"

check "a later run of the start script exits zero" as_root "${INCUS_START}"
check "the start script changed no pool or network" test "$(pools_and_networks)" = "${after_first}"
check "an instance starts and gets an address on the preseed's bridge" instance_starts_with_address
check "the instance is removed" remove_instance

rm -f "${preseed}"
reportResults
