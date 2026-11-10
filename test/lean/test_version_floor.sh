#!/usr/bin/env bash
# Scenario "test_version_floor": fedora:44 as root with elanVersion 4.1.0, the minimum, a named defaultToolchain, and a
# build-time toolchain, which that release resolves through the release index ("Pinned release", "Named default
# toolchain", "Listed toolchains"); then the installer again with the same options ("Same options", "Toolchain already
# in the image").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly IMAGE_TOOLCHAIN="/usr/local/share/lean/toolchains/leanprover--lean4---v4.35.0"

work_dir=""
installer="$(dirname "$(readlink -f "$0")")/_feature/install.sh"
readonly installer

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

default_is_named() {
  local shown
  shown="$(cd / && elan show)"
  [[ "${shown}" == *"leanprover/lean4:v4.35.0 (default)"* ]]
}

# Prints the inode and modification time of elan and of the build-time toolchain.
installed_state() {
  stat -c '%i %Y' /usr/local/bin/elan "${IMAGE_TOOLCHAIN}"
}

# Runs the installer as root with the scenario's options again; keeps its output.
install_again() {
  ELANVERSION=4.1.0 DEFAULTTOOLCHAIN=leanprover/lean4:v4.35.0 PREINSTALLTOOLCHAINS=leanprover/lean4:v4.35.0 \
    bash "${installer}" >"${work_dir}/again.log" 2>&1
}

# Whether the second install's log holds no download: install.sh logs "lean: downloading <url>" for elan, and elan
# logs "info: downloading <url>" for a toolchain.
downloaded_nothing() {
  ! grep -qE '^(lean|info): downloading ' "${work_dir}/again.log"
}

trap cleanup EXIT
work_dir="$(mktemp -d)"

check "elan --version reports exactly the pinned release" reports_minimum
check "the build-time toolchain is in the image" test -x "${IMAGE_TOOLCHAIN}/bin/lean"
check "the build-time toolchain is linked into elan's home" \
  test -L /var/lib/lean/elan/toolchains/leanprover--lean4---v4.35.0
check "a project pinned to the build-time toolchain builds and its executable runs" project_runs
check "elan show names the named toolchain as the default" default_is_named

before="$(installed_state)"
check "a second install with the same options succeeds" install_again
check "the second install downloads no elan release and no toolchain" downloaded_nothing
check "the second install leaves elan and the build-time toolchain as they were" \
  [ "$(installed_state)" == "${before}" ]

reportResults
