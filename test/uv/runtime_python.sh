#!/usr/bin/env bash
# Scenario "runtime_python": defaults on the Ubuntu base image as vscode ("Runtime interpreter on the volume",
# "Workspace install across filesystems").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly VOLUME_DIR="/var/lib/uv"

work_dir="$(mktemp -d)"
uv_log="${work_dir}/uv.log"
# A named volume and a bind-mounted workspace can share the runner's backing filesystem, so the test exercises
# UV_LINK_MODE across actual filesystems with a temporary cache on Docker's tmpfs.
cross_fs_cache="$(mktemp -d /dev/shm/uv-cross-filesystems.XXXXXX)"

is_empty_dir() {
  [[ -d "$1" && -z "$(ls -A "$1")" ]]
}

# Whether the interpreter link $1 resolves to an executable below the volume's python directory.
resolves_to_volume() {
  local target
  target="$(readlink -f "$1")"
  printf '%s\n' "$1 -> ${target}"
  [[ "${target}" == "${VOLUME_DIR}"/python/* && -x "${target}" ]]
}

# Creates the environment $1 and installs pycowsay into it with the cross-filesystem cache; further arguments go to
# uv pip install. uv's output, where a link-mode warning would appear, goes to uv_log and is printed.
install_into() {
  local env_dir="$1"
  shift
  uv venv "${env_dir}" || return
  if ! UV_CACHE_DIR="${cross_fs_cache}" uv pip install --python "${env_dir}/bin/python" "$@" pycowsay \
    >"${uv_log}" 2>&1; then
    cat "${uv_log}"
    return 1
  fi
  cat "${uv_log}"
}

no_link_mode_warning() {
  ! grep -Eqi 'hardlink|clone|falling back|link mode' "${uv_log}"
}

check "the volume is new and empty" is_empty_dir "${VOLUME_DIR}"

# Runtime interpreter on the volume.
check "the remote user creates a virtual environment with a uv-managed interpreter" \
  uv venv --managed-python "${work_dir}/venv"
check "the interpreter is installed under ${VOLUME_DIR}" [ -n "$(ls -A "${VOLUME_DIR}/python")" ]
check "the environment's interpreter link resolves there" resolves_to_volume "${work_dir}/venv/bin/python"

# Workspace install across filesystems: the working directory is the bind-mounted workspace.
check "the workspace and the test cache are on different filesystems" \
  [ "$(stat -c %d .)" != "$(stat -c %d "${cross_fs_cache}")" ]
check "the remote user installs a package into an environment in the workspace" install_into .venv-uv-first
check "uv reports no link-mode fallback warning" no_link_mode_warning
check "the remote user installs the package from the cache into another workspace environment, offline" \
  install_into .venv-uv-second --offline
check "uv reports no link-mode fallback warning for the install from the cache" no_link_mode_warning
check "the installed package runs" ./.venv-uv-second/bin/pycowsay hello

rm -rf .venv-uv-first .venv-uv-second "${work_dir}" "${cross_fs_cache}"

reportResults
