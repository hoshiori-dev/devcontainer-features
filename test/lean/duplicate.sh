#!/usr/bin/env bash
# Install-twice test: lean is installed with elanVersion 4.1.0, defaultToolchain leanprover/lean4:v4.35.0, and
# preinstallToolchains leanprover/lean4:v4.35.0, then with the defaults, on each compatibility image; runs as the
# remote user after the container-creation script ran. It also runs the build-time toolchain on every listed image.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly TOOLCHAIN="leanprover--lean4---v4.35.0"
readonly IMAGE_TOOLCHAIN="/usr/local/share/lean/toolchains/${TOOLCHAIN}"
readonly VOLUME_TOOLCHAIN="/var/lib/lean/elan/toolchains/${TOOLCHAIN}"

# Whether nothing under /usr/local/share/lean belongs to another user than root or, apart from links, is writable by
# its group or by every user.
share_dir_root_only() {
  [[ -z "$(find /usr/local/share/lean ! -user root -print -quit)" ]] \
    && [[ -z "$(find /usr/local/share/lean ! -type l -perm /022 -print -quit)" ]]
}

# Whether the remote user is listed once in the group lean, which exists once.
listed_once_in_lean() {
  [[ "$(grep -c '^lean:' /etc/group)" == "1" ]] \
    && [[ "$(grep '^lean:' /etc/group | cut -d: -f4 | tr ',' '\n' | grep -cx "$(id -un)")" == "1" ]]
}

# Creates a Lake project pinned to v4.35.0 in a temporary directory, builds it with Lake's artifact cache enabled, and
# runs its executable; prints the executable's output.
build_project() {
  local dir
  dir="$(mktemp -d)"
  cd "${dir}"
  lake +leanprover/lean4:v4.35.0 new demo >/dev/null
  cd demo
  LAKE_ARTIFACT_CACHE=true lake build >&2
  ./.lake/build/bin/demo
}

project_runs() {
  local output
  output="$(build_project)"
  [[ "${output}" == "Hello, world!" ]]
}

# Whether elan --version reports the release the test expects.
reports_release() {
  local line
  line="$(elan --version)"
  [[ "${line}" == "elan ${release} "* ]]
}

# Whether elan show, run outside any project, names $1 as the default it resolves from.
default_is() {
  local shown
  shown="$(cd / && elan show)"
  [[ "${shown}" == *"(resolved from default '$1')"* ]]
}

# Whether elan toolchain list names the toolchain $1, alone or followed by a remark such as "(default)".
lists_toolchain() {
  local name
  while read -r name _; do
    if [[ "${name}" == "$1" ]]; then return 0; fi
  done < <(elan toolchain list)
  return 1
}

artifacts_in_lake_cache() {
  [[ -n "$(find "${LAKE_CACHE_DIR}" -name '*.olean' -print -quit)" ]]
}

# Different options. The release the redirect names when the test runs cannot be a literal; a release published
# between the image build and the test fails once.
latest_url="$(curl --proto '=https' -fsS -o /dev/null -w '%{redirect_url}' \
  https://github.com/leanprover/elan/releases/latest)"
release="${latest_url##*/v}"
check "elan --version reports the second install's release" reports_release
check "the default toolchain after creation is the second install's" default_is stable
check "the first install's toolchain is in the image" test -d "${IMAGE_TOOLCHAIN}"
check "nothing under /usr/local/share/lean is writable by another user than root" share_dir_root_only
check "the build-time toolchain is linked into elan's home" \
  [ "$(readlink "${VOLUME_TOOLCHAIN}")" == "${IMAGE_TOOLCHAIN}" ]
check "elan lists the build-time toolchain as installed" lists_toolchain leanprover/lean4:v4.35.0
if [[ "$(id -u)" != "0" ]]; then
  check "the group lean lists the remote user once" listed_once_in_lean
fi

# New Lake project, Lake artifact cache with a build-time toolchain, and the toolchain running on this image.
check "a project pinned to the build-time toolchain builds and its executable runs" project_runs
check "the toolchain was not downloaded again" [ -L "${VOLUME_TOOLCHAIN}" ]
check "Lake stores the artifacts under LAKE_CACHE_DIR" artifacts_in_lake_cache

reportResults
