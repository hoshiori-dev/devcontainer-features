#!/usr/bin/env bash
# Scenario "test_dind": docker-in-docker and firewall (presets npm, allowedCidrs 185.199.108.0/22, filterForward omitted).
# A nested container on a user-defined network reaches an address inside the allowed range, one of
# raw.githubusercontent.com's without a lookup, and is refused a host that no option allows ("With docker-in-docker",
# "Nested container filtered", "Nested container reaches an allowed range", "Omitted filterForward"). That a nested
# container reaches an allowed domain is not asserted: the feature does not guarantee it (Requirement: Forwarded
# traffic).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

work_dir="$(mktemp -d)"

# Imports this container's own root file system as the image firewall-test/rootfs, so that no test pulls from a
# registry, and creates the user-defined network firewall-test. The archive leaves out what curl in a nested container
# does not need: the nested Docker daemon's programs and data, and /run, whose files change while that daemon runs.
nested_setup() {
  tar -C / --one-file-system -cf "${work_dir}/rootfs.tar" --exclude=./proc --exclude=./sys --exclude=./dev \
    --exclude=./tmp --exclude=./run --exclude=./var/lib/docker --exclude=./var/cache --exclude=./var/lib/apt \
    --exclude=./usr/share --exclude=./usr/local --exclude=./usr/libexec/docker --exclude='./usr/bin/docker*' \
    --exclude='./usr/bin/containerd*' --exclude=./usr/bin/ctr --exclude=./usr/bin/runc .
  docker import "${work_dir}/rootfs.tar" firewall-test/rootfs
  rm "${work_dir}/rootfs.tar"
  docker network create firewall-test
}

# Runs curl with the arguments $@ in a nested container on the user-defined network; its status is curl's.
nested_curl() {
  docker run --rm --network firewall-test firewall-test/rootfs \
    /usr/bin/curl -q -sS -o /dev/null --connect-timeout 10 --max-time 30 "$@"
}

# Whether a nested container reaches raw.githubusercontent.com at the address $1, without a lookup.
nested_raw_at() {
  nested_curl --resolve "raw.githubusercontent.com:443:$1" https://raw.githubusercontent.com/
}

# Whether a nested container's request with the curl arguments $@ is refused: curl ends with status 7.
nested_refused() {
  local status=0
  nested_curl "$@" || status=$?
  printf 'nested curl exit status %s\n' "${status}"
  [[ "${status}" -eq 7 ]]
}

forward_chain_loaded() {
  local table
  table="$(table_listing)" || return 1
  [[ "${table}" == *"hook forward"* ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# With docker-in-docker
check "the nested Docker daemon starts" wait_for_docker
nested_setup

# Omitted filterForward, Nested container filtered
check "without filterForward, the rules filter forwarded traffic" forward_chain_loaded
check "a nested container's connection to github.com, a host no option allows, is refused" \
  nested_refused https://github.com/

# Nested container reaches an allowed range. It also shows that the nested daemon runs a nested container.
check "a nested container's connection to 185.199.109.133, inside the allowed range, succeeds" \
  nested_raw_at 185.199.109.133

# Deviation from shell-style.md (Tests): this label uses the words of the design's Goal "One owned table, replaced
# atomically", an invariant of the approach that no scenario of the spec states.
check "the feature's table is still in place beside the nested container's rules" nft list table inet firewall

rm -rf "${work_dir}"
reportResults
