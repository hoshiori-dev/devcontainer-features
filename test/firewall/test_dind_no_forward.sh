#!/usr/bin/env bash
# Scenario "test_dind_no_forward": docker-in-docker and firewall (presets npm, filterForward false). A nested container
# on
# a user-defined network reaches github.com, which no option allows, while the dev container itself is refused it
# ("Forwarded traffic not filtered").
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

# Whether a request with the curl arguments $@, made in a nested container on the user-defined network, completes.
nested_reachable() {
  docker run --rm --network firewall-test firewall-test/rootfs \
    /usr/bin/curl -q -sS -o /dev/null --connect-timeout 10 --max-time 30 "$@"
}

no_forward_chain() {
  local table
  table="$(table_listing)" || return 1
  [[ "${table}" != *"hook forward"* ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes
check "the nested Docker daemon starts" wait_for_docker
nested_setup

# Forwarded traffic not filtered
check "with filterForward disabled, the rules do not filter forwarded traffic" no_forward_chain
check "a nested container's connection to github.com, a host no option allows, is not refused" \
  nested_reachable https://github.com/
check "the dev container's own connection to github.com, which no option allows, is refused" \
  refused https://github.com/

rm -rf "${work_dir}"
reportResults
