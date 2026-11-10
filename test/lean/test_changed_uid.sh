#!/usr/bin/env bash
# Scenario "test_changed_uid": debian:13 with the remote user developer, built with UID 23456, whose UID the dev
# container tooling changed to the host user's, and a group lean without members in the image ("Changed UID", "Remote
# user in the group", "Existing group", "Toolchain installed on first use", "Volume that fits").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly VOLUME_DIR="/var/lib/lean"
readonly INITIALIZE="/usr/local/share/lean-feature/initialize"
# The UID test_changed_uid/Dockerfile gives the remote user at build time.
readonly BUILD_UID=23456

work_dir=""

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm -rf "${work_dir}"; fi
}

member_of_lean() {
  [[ " $(id -Gn) " == *" lean "* ]]
}

# Whether the creation step's directories exist and belong to the remote user under its new UID.
directories_prepared() {
  local dir
  for dir in elan/toolchains cache/lake cache/mathlib; do
    [[ "$(stat -c %u "${VOLUME_DIR}/${dir}")" == "$(id -u)" ]] || return 1
  done
}

default_is_stable() {
  local shown
  shown="$(cd / && elan show)"
  [[ "${shown}" == *"(resolved from default 'stable')"* ]]
}

# Creates a Lake project pinned to v4.35.0, which elan installs on first use, and builds it.
project_runs() {
  local output
  output="$(cd "${work_dir}" && lake +leanprover/lean4:v4.35.0 new demo >/dev/null && cd demo && lake build >&2 \
    && ./.lake/build/bin/demo)"
  [[ "${output}" == "Hello, world!" ]]
}

toolchain_on_volume() {
  [[ -d "${VOLUME_DIR}/elan/toolchains/leanprover--lean4---v4.35.0" ]] \
    && [[ ! -L "${VOLUME_DIR}/elan/toolchains/leanprover--lean4---v4.35.0" ]]
}

trap cleanup EXIT
work_dir="$(mktemp -d)"

check "the tooling changed the remote user's UID" [ "$(id -u)" != "${BUILD_UID}" ]
check "the remote user no longer owns the new volume" [ "$(stat -c %u "${VOLUME_DIR}")" != "$(id -u)" ]
check "the remote user is a member of the group lean" member_of_lean
check "the existing group lean keeps its ID" [ "$(getent group lean | cut -d: -f3)" == "23458" ]
check "the new volume belongs to the group lean and is writable by its members" \
  [ "$(stat -c '%G %a' "${VOLUME_DIR}")" == "lean 2775" ]
check "the creation step prepared the volume for the remote user" directories_prepared
check "the creation step set the default toolchain" default_is_stable

warning="$(mktemp)"
check "the creation step succeeds again on the volume, which fits" "${INITIALIZE}" 2>"${warning}"
check "no warning is printed on a volume that fits" test ! -s "${warning}"
rm "${warning}"

check "the remote user installs a toolchain on first use and builds a project" project_runs
check "elan installed the toolchain under ${VOLUME_DIR}/elan/toolchains" toolchain_on_volume

reportResults
