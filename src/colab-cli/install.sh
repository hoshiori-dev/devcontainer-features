#!/usr/bin/env bash
# Installs google-colab-cli from PyPI using uv tool install to /usr/local/share/uv/tools and bin, with managed CPython
# from Astral's python-build-standalone releases under /usr/local/share/uv/python. uv verifies index package hashes and
# interpreter checksums. Runs as root at image build time; the option `version` arrives as VERSION.
set -euo pipefail

readonly UV_PATH="/usr/local/bin/uv"
readonly SHARE_DIR="/usr/local/share/uv"
readonly TOOL_DIR="${SHARE_DIR}/tools"
readonly BIN_DIR="${SHARE_DIR}/bin"
readonly PYTHON_DIR="${SHARE_DIR}/python"
readonly TOOL_ENV="${TOOL_DIR}/google-colab-cli"
readonly MINIMUM_UV_VERSION="0.12.16"
readonly PACKAGE_INDEX_URL="https://pypi.org/simple/google-colab-cli/"
readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="${SYSTEM_PATH}"

VERSION="${VERSION-latest}"
work_dir=""
remote_user=""
remote_group=""
latest_version=""

log() {
  printf 'colab-cli: %s\n' "$*"
}

fail() {
  printf 'colab-cli: error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\"; use latest or an exact release such as 0.7.2"
  fi
}

detect_platform() {
  local os_id
  local arch
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in
    debian | ubuntu) ;;
    *) fail "unsupported distribution \"${os_id}\"; use a Debian or Ubuntu image" ;;
  esac
  arch="$(uname --machine)"
  case "${arch}" in
    x86_64 | aarch64) ;;
    *) fail "unsupported architecture \"${arch}\"; use amd64 or arm64" ;;
  esac
  readonly VERSION
}

check_dependency() {
  local uv_output
  local uv_version
  local major
  local minor
  local patch
  [[ -x "${UV_PATH}" ]] || fail "uv is missing; install the declared uv dependency first"
  uv_output="$("${UV_PATH}" --version)"
  uv_version="${uv_output#uv }"
  uv_version="${uv_version%% *}"
  [[ "${uv_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "cannot read uv version from \"${uv_output}\"; use uv ${MINIMUM_UV_VERSION} or later"
  IFS=. read -r major minor patch <<<"${uv_version}"
  if (( 10#${major} == 0 && (10#${minor} < 12 || (10#${minor} == 12 && 10#${patch} < 16)) )); then
    fail "uv ${uv_version} does not verify package hashes; use uv ${MINIMUM_UV_VERSION} or later"
  fi
  remote_user="${_REMOTE_USER:-root}"
  id "${remote_user}" >/dev/null 2>&1 || fail "remote user ${remote_user} is missing; create it before installing"
  if [[ "$(id --user "${remote_user}")" == 0 ]]; then
    remote_group="$(id --group --name "${remote_user}")"
  else
    remote_group=uv
    [[ " $(id --groups --name "${remote_user}") " == *" uv "* ]] \
      || fail "remote user ${remote_user} is not in group uv; install the uv dependency for that user first"
  fi
}

# Only the directories and interpreter policy needed for this build enter uv's environment.
run_uv() {
  env --ignore-environment PATH="${SYSTEM_PATH}" HOME="${work_dir}" LANG=C.UTF-8 \
    UV_CACHE_DIR="${work_dir}/cache" UV_PYTHON_INSTALL_DIR="${PYTHON_DIR}" UV_TOOL_DIR="${TOOL_DIR}" \
    UV_TOOL_BIN_DIR="${BIN_DIR}" UV_LINK_MODE=copy \
    "${UV_PATH}" --no-config "$@"
}

install_tool() {
  local installed_version=""
  local package=google-colab-cli
  local upgrade_args=()
  local interpreter_ok=false
  if [[ -x "${TOOL_ENV}/bin/python" ]]; then
    installed_version="$(env --ignore-environment "${TOOL_ENV}/bin/python" -I -c \
      'from importlib.metadata import version; print(version("google-colab-cli"))')"
    if env --ignore-environment "${TOOL_ENV}/bin/python" -I -c '
import sys
from pathlib import Path
sys.exit(not (sys.version_info[:2] == (3, 12)
             and Path(sys.executable).resolve().is_relative_to("/usr/local/share/uv/python")))'; then
      interpreter_ok=true
    else
      upgrade_args=(--reinstall)
    fi
  fi
  if [[ "${VERSION}" != latest && "${installed_version}" == "${VERSION}" && "${interpreter_ok}" == true ]]; then
    log "google-colab-cli ${VERSION} is already installed; skipping package installation"
    return
  fi
  if [[ "${VERSION}" == latest && -n "${installed_version}" && "${interpreter_ok}" == true ]]; then
    resolve_latest
    if [[ "${installed_version}" == "${latest_version}" ]]; then
      log "google-colab-cli ${latest_version} is already the newest stable release; skipping package installation"
      return
    fi
  fi
  if [[ "${VERSION}" == latest ]]; then
    upgrade_args+=(--upgrade-package google-colab-cli)
  else
    package="google-colab-cli==${VERSION}"
  fi
  log "installing ${package} from PyPI with uv to ${TOOL_ENV}, using managed Python 3.12 in ${PYTHON_DIR}"
  run_uv tool install --python 3.12 --managed-python "${upgrade_args[@]}" "${package}" \
    || fail "cannot install google-colab-cli ${VERSION}; check the PyPI release and network access"
  installed_version="$(env --ignore-environment "${TOOL_ENV}/bin/python" -I -c \
    'from importlib.metadata import version; print(version("google-colab-cli"))')"
  if [[ "${VERSION}" != latest && "${installed_version}" != "${VERSION}" ]]; then
    fail "installed release ${installed_version} differs from requested ${VERSION}; reinstall the requested release"
  fi
}

# uv can select an older compatible release if the newest release needs a newer Python; never silently call it latest.
resolve_latest() {
  log "checking the newest stable release from ${PACKAGE_INDEX_URL}"
  env --ignore-environment PATH="${SYSTEM_PATH}" HOME="${work_dir}" curl --disable \
    --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
    --header 'Accept: application/vnd.pypi.simple.v1+json' --output "${work_dir}/index.json" "${PACKAGE_INDEX_URL}" \
    || fail "cannot read the official package index; check network access to PyPI"
  latest_version="$(env --ignore-environment "${TOOL_ENV}/bin/python" -I -B - "${work_dir}/index.json" <<'PY'
import json
import sys
from packaging.utils import parse_sdist_filename, parse_wheel_filename

with open(sys.argv[1]) as source:
    files = json.load(source)["files"]
releases = set()
for file in files:
    if file["yanked"]:
        continue
    name = file["filename"]
    release = (parse_wheel_filename(name) if name.endswith(".whl") else parse_sdist_filename(name))[1]
    if not release.is_prerelease and not release.is_devrelease:
        releases.add(release)
print(max(releases))
PY
)" || fail "cannot resolve the newest stable release from the official index; check PyPI metadata"
}

verify_latest() {
  local installed_version
  if [[ "${VERSION}" != latest ]]; then return; fi
  if [[ -z "${latest_version}" ]]; then resolve_latest; fi
  installed_version="$(env --ignore-environment "${TOOL_ENV}/bin/python" -I -c \
    'from importlib.metadata import version; print(version("google-colab-cli"))')"
  [[ "${installed_version}" == "${latest_version}" ]] \
    || fail "installed ${installed_version} instead of latest ${latest_version}; pin a release or review Python support"
}

# Group access preserves tool management when Dev Containers changes the remote user's UID.
set_permissions() {
  local interpreter
  local interpreter_dir
  interpreter="$(readlink --canonicalize "${TOOL_ENV}/bin/python")"
  # CPython builds keep bin/python below their interpreter root; do not change other managed interpreter trees.
  interpreter_dir="${interpreter%/bin/*}"
  [[ "${interpreter_dir}" == "${PYTHON_DIR}/"* ]] \
    || fail "tool interpreter is outside ${PYTHON_DIR}; reinstall with managed Python 3.12"
  log "setting ${TOOL_ENV}, its executable, and managed interpreters for ${remote_user}:${remote_group}"
  # Change only entries that need it: chmod/chown on an unchanged tree would copy every file in a layered image.
  find "${TOOL_ENV}" "${interpreter_dir}" \( ! -user "${remote_user}" -o ! -group "${remote_group}" \) \
    -exec chown --no-dereference "${remote_user}:${remote_group}" {} +
  chown --no-dereference "${remote_user}:${remote_group}" "${PYTHON_DIR}"
  if [[ -e "${PYTHON_DIR}/.lock" ]]; then
    chown "${remote_user}:${remote_group}" "${PYTHON_DIR}/.lock"
  fi
  chown --no-dereference "${remote_user}:${remote_group}" "${BIN_DIR}/colab"
  if [[ "$(id --user "${remote_user}")" == 0 ]]; then
    find "${TOOL_ENV}" "${interpreter_dir}" \( -type f -o -type d \) -perm /0022 -exec chmod go-w {} +
    chmod go-w "${PYTHON_DIR}"
  else
    find "${TOOL_ENV}" "${interpreter_dir}" \( -type f -o -type d \) \( ! -perm -0020 -o -perm -0002 \) \
      -exec chmod g+w,o-w {} +
    chmod g+ws,o-w "${PYTHON_DIR}"
    find "${TOOL_ENV}" "${interpreter_dir}" -type d ! -perm -2000 -exec chmod g+s {} +
  fi
  if [[ -e "${PYTHON_DIR}/.lock" ]]; then
    if [[ "${remote_group}" == uv ]]; then
      chmod g+w,o-w "${PYTHON_DIR}/.lock"
    else
      chmod go-w "${PYTHON_DIR}/.lock"
    fi
  fi
}

main() {
  validate_options
  detect_platform
  check_dependency
  trap cleanup EXIT
  work_dir="$(mktemp --directory)"
  install_tool
  verify_latest
  env --ignore-environment HOME="${work_dir}" PATH="${SYSTEM_PATH}" "${BIN_DIR}/colab" version \
    || fail "colab version failed; check the installed tool environment"
  env --ignore-environment HOME="${work_dir}" PATH="${SYSTEM_PATH}" "${BIN_DIR}/colab" --help \
    || fail "colab help failed; check the installed tool environment"
  # The probes can create Python bytecode directories; include them in the final permission pass.
  set_permissions
}

main "$@"
