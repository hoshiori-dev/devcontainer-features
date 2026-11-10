#!/usr/bin/env bash
# Scenario "test_version_floor": fedora:44 as root with elanVersion 4.1.0, the minimum, and a build-time toolchain,
# which that release resolves through the release index ("Pinned release", "Listed toolchains").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

work_dir=""

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm -rf "${work_dir}"; fi
}

reports_minimum() {
  local line
  line="$(elan --version)"
  [[ "${line}" == "elan 4.1.0 "* ]]
}

project_runs() {
  local output
  output="$(cd "${work_dir}" && lake +leanprover/lean4:v4.35.0 new demo >/dev/null && cd demo && lake build >&2 \
    && ./.lake/build/bin/demo)"
  [[ "${output}" == "Hello, world!" ]]
}

default_is_stable() {
  local shown
  shown="$(cd / && elan show)"
  [[ "${shown}" == *"(resolved from default 'stable')"* ]]
}

trap cleanup EXIT
work_dir="$(mktemp -d)"

check "elan --version reports exactly the pinned release" reports_minimum
check "the build-time toolchain is in the image" test -x /usr/local/share/lean/toolchains/leanprover--lean4---v4.35.0/bin/lean
check "the build-time toolchain is linked into elan's home" \
  test -L /var/lib/lean/elan/toolchains/leanprover--lean4---v4.35.0
check "a project pinned to the build-time toolchain builds and its executable runs" project_runs
check "elan show names stable as the default" default_is_stable

reportResults
