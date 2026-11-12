#!/usr/bin/env bash
# Scenario "test_offline_toolchains": the base image as vscode, with two names for one build-time toolchain, whitespace,
# and an empty entry in preinstallToolchains, in a container without a network ("Listed toolchains", "Build-time
# toolchain linked", "Toolchain of the same name on the volume", "Toolchain dropped from the image", "Build-time
# toolchain uninstalled", the offline fallback of a stable default).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly NAME="leanprover--lean4---v4.35.0"
readonly IMAGE_DIR="/usr/local/share/lean/toolchains"
readonly VOLUME_DIR="/var/lib/lean/elan/toolchains"
readonly INITIALIZE="/usr/local/share/lean-feature/initialize"

work_dir=""

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm -rf "${work_dir}"; fi
}

no_network() {
  ! curl -fsS --max-time 5 -o /dev/null https://release.lean-lang.org 2>/dev/null
}

# Creates a Lake project pinned to v4.35.0 and builds it; prints the executable's output.
build_project() {
  cd "${work_dir}"
  lake +leanprover/lean4:v4.35.0 new demo >/dev/null
  cd demo
  lake build >&2
  ./.lake/build/bin/demo
}

project_runs_offline() {
  local output
  output="$(build_project)"
  [[ "${output}" == "Hello, world!" ]]
}

# Whether lean, run outside any project with the stable default, falls back to the build-time release offline.
stable_falls_back_offline() {
  local output
  output="$(cd / && lean --version 2>/dev/null)"
  [[ "${output}" == "Lean (version 4.35.0,"* ]]
}

links_to_image() {
  [[ "$(readlink "${VOLUME_DIR}/${NAME}")" == "${IMAGE_DIR}/${NAME}" ]]
}

# Whether nothing under /usr/local/share/lean belongs to another user than root or, apart from links, is writable by
# its group or by every user.
share_dir_root_only() {
  [[ -z "$(find /usr/local/share/lean ! -user root -print -quit)" ]] \
    && [[ -z "$(find /usr/local/share/lean ! -type l -perm /022 -print -quit)" ]]
}

entry_absent() {
  [[ ! -e "${VOLUME_DIR}/${NAME}" && ! -L "${VOLUME_DIR}/${NAME}" ]]
}

volume_directory_kept() {
  [[ ! -L "${VOLUME_DIR}/${NAME}" && -e "${VOLUME_DIR}/${NAME}/marker" ]]
}

umask 022
trap cleanup EXIT
work_dir="$(mktemp -d)"

check "the container has no network" no_network
check "the two names install one toolchain into the image" [ "$(ls -A "${IMAGE_DIR}")" == "${NAME}" ]
check "the build-time toolchain is linked into elan's home" links_to_image
check "nothing under /usr/local/share/lean is writable by another user than root" share_dir_root_only

# Listed toolchains.
check "a project pinned to the build-time toolchain builds offline and its executable runs" project_runs_offline
check "a stable default falls back to the build-time release offline" stable_falls_back_offline

# Build-time toolchain uninstalled.
elan toolchain uninstall leanprover/lean4:v4.35.0
check "uninstalling removes only the link" entry_absent
check "the toolchain in the image is unchanged" test -x "${IMAGE_DIR}/${NAME}/bin/lean"
"${INITIALIZE}"
check "the next creation links it again" links_to_image

# Toolchain dropped from the image: a dangling link into the image directory goes, a foreign one stays.
ln -s "${IMAGE_DIR}/leanprover--lean4---v4.0.0" "${VOLUME_DIR}/leanprover--lean4---v4.0.0"
ln -s /nonexistent/toolchain "${VOLUME_DIR}/foreign"
"${INITIALIZE}"
check "a link to a toolchain the image no longer holds is removed" \
  [ ! -L "${VOLUME_DIR}/leanprover--lean4---v4.0.0" ]
check "a link to another target stays" [ "$(readlink "${VOLUME_DIR}/foreign")" == "/nonexistent/toolchain" ]
check "the build-time toolchain's link stays" links_to_image
rm "${VOLUME_DIR}/foreign"

# Toolchain of the same name on the volume.
rm "${VOLUME_DIR}/${NAME}"
mkdir "${VOLUME_DIR}/${NAME}"
touch "${VOLUME_DIR}/${NAME}/marker"
"${INITIALIZE}"
check "a directory of the same name on the volume stays and no link replaces it" volume_directory_kept
rm -r "${VOLUME_DIR:?}/${NAME}"
"${INITIALIZE}"
check "the link comes back once the directory is gone" links_to_image

reportResults
