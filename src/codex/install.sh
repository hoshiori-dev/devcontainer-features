#!/usr/bin/env bash
# Installs complete official Codex native packages from GitHub Releases, verified against release SHA-256 sums,
# to /usr/local/share/codex. Runs as root at image build time; option version arrives as VERSION.
set -euo pipefail

readonly RELEASE_API="https://api.github.com/repos/openai/codex/releases"
readonly RELEASE_URL="https://github.com/openai/codex/releases/download"
readonly APPLICATION_DIR="/usr/local/share/codex"
readonly CLI_PATH="/usr/local/bin/codex"
readonly HELPER_DIR="/usr/local/share/codex-feature"
readonly STATE_DIR="/var/lib/codex"
VERSION="${VERSION-latest}"
work_dir=""
platform_target=""

log() { printf 'codex: %s\n' "$*"; }
fail() { printf 'codex: error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

validate_environment() {
  local os_id os_version architecture home_path
  [[ "$(uname --kernel-name)" == Linux ]] || fail "unsupported system; official Linux native packages are required"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  case "${os_id}:${os_version}" in
    debian:12 | ubuntu:24.04) ;;
    *) log "warning: untested distribution ${os_id} ${os_version}; attempting the official native package" ;;
  esac
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64) platform_target="x86_64-unknown-linux-musl" ;;
    aarch64) platform_target="aarch64-unknown-linux-musl" ;;
    *) fail "unsupported architecture ${architecture}; no matching official native package" ;;
  esac
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid version; use latest or an exact stable MAJOR.MINOR.PATCH release"
  fi
  readonly VERSION
  [[ "${CODEX_HOME+x}" != x ]] || fail "CODEX_HOME is configured; remove the override before using this feature"
  home_path="${_REMOTE_USER_HOME:-$(getent passwd "${_REMOTE_USER:-root}" | cut --delimiter=: --fields=6)}"
  [[ -d "${home_path}" && "${home_path}" == /* ]] || fail "remote-user home is unavailable; configure remoteUser"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory; preserve it and resolve the mount path"
  if [[ -L "${home_path}/.codex" ]]; then
    [[ "$(readlink --canonicalize-existing "${home_path}/.codex")" == "${STATE_DIR}" ]] \
      || fail "existing .codex link conflicts; preserve it and resolve the mapping manually"
  elif [[ -e "${home_path}/.codex" ]]; then
    fail "existing .codex content conflicts; preserve it and migrate it explicitly before enabling this feature"
  fi
}

# Bootstrap only missing native-package tools, using the image's configured repositories and verification.
install_prerequisites() {
  local tool missing=false
  for tool in curl jq tar gzip sha256sum mountpoint find getent; do
    if ! command -v "${tool}" >/dev/null; then missing=true; fi
  done
  if [[ "${missing}" == false ]]; then return; fi
  log "installing native-package download and initialization prerequisites"
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes --no-install-recommends ca-certificates curl jq tar gzip coreutils findutils util-linux
    rm --recursive --force /var/lib/apt/lists/*
  elif command -v apk >/dev/null; then
    apk add --no-cache ca-certificates curl jq tar gzip coreutils findutils util-linux musl-utils
  elif command -v dnf >/dev/null; then
    dnf install --assumeyes ca-certificates curl jq tar gzip coreutils findutils util-linux
    dnf clean all
  elif command -v microdnf >/dev/null; then
    microdnf install --assumeyes ca-certificates curl jq tar gzip coreutils findutils util-linux
    microdnf clean all
  elif command -v yum >/dev/null; then
    yum install --assumeyes ca-certificates curl jq tar gzip coreutils findutils util-linux
    yum clean all
  else
    fail "native-package prerequisites are missing; install curl, jq, tar, gzip, coreutils, findutils and util-linux"
  fi
}

fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

install_release() {
  local endpoint resolved asset base_url expected installed=""
  work_dir="$(mktemp --directory /usr/local/share/.codex-install.XXXXXX)"
  trap cleanup EXIT
  mkdir --parents "${work_dir}/home"
  endpoint="${RELEASE_API}/tags/rust-v${VERSION}"
  if [[ "${VERSION}" == latest ]]; then endpoint="${RELEASE_API}/latest"; fi
  log "resolving official native Codex release ${VERSION}"
  fetch --output "${work_dir}/release.json" "${endpoint}" \
    || fail "cannot resolve release; check the version and official GitHub access"
  resolved="$(jq --exit-status --raw-output \
    'select(.draft == false and .prerelease == false) | .tag_name | capture("^rust-v(?<version>[0-9]+\\.[0-9]+\\.[0-9]+)$").version' \
    "${work_dir}/release.json")" || fail "release is not stable; select a supported stable version"
  [[ "${VERSION}" == latest || "${VERSION}" == "${resolved}" ]] || fail "release metadata does not match requested version"
  asset="codex-package-${platform_target}.tar.gz"
  jq --exit-status --arg asset "${asset}" 'any(.assets[]; .name == $asset)' "${work_dir}/release.json" >/dev/null \
    || fail "unsupported target for release ${resolved}; official native package ${asset} is unavailable"
  if [[ -x "${APPLICATION_DIR}/bin/codex" ]]; then
    installed="$(env -u CODEX_HOME HOME="${work_dir}/home" "${APPLICATION_DIR}/bin/codex" --version)" || installed=""
  fi
  if [[ "${installed}" == "codex-cli ${resolved}" \
    && -x "${APPLICATION_DIR}/bin/codex-code-mode-host" && -x "${APPLICATION_DIR}/codex-path/rg" ]]; then return; fi
  base_url="${RELEASE_URL}/rust-v${resolved}"
  fetch --output "${work_dir}/SHA256SUMS" "${base_url}/codex-package_SHA256SUMS" \
    || fail "cannot download required release checksum manifest"
  expected="$(awk -v asset="${asset}" '$2 == asset {print $1}' "${work_dir}/SHA256SUMS")"
  [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "release checksum manifest has no unique valid native package checksum"
  fetch --output "${work_dir}/${asset}" "${base_url}/${asset}" || fail "cannot download official native package"
  printf '%s  %s\n' "${expected}" "${work_dir}/${asset}" | sha256sum --check --quiet \
    || fail "native package checksum verification failed"
  mkdir --parents "${work_dir}/application"
  tar --extract --gzip --no-same-owner --file "${work_dir}/${asset}" --directory "${work_dir}/application"
  [[ -x "${work_dir}/application/bin/codex" && -x "${work_dir}/application/bin/codex-code-mode-host" \
    && -x "${work_dir}/application/codex-path/rg" ]] || fail "native package is incomplete; required companion files are missing"
  chmod 0755 "${work_dir}/application/bin/codex" "${work_dir}/application/bin/codex-code-mode-host" \
    "${work_dir}/application/codex-path/rg"
  if [[ -f "${work_dir}/application/codex-resources/bwrap" ]]; then
    chmod 0755 "${work_dir}/application/codex-resources/bwrap"
  fi
  [[ "$(env -u CODEX_HOME HOME="${work_dir}/home" "${work_dir}/application/bin/codex" --version)" == "codex-cli ${resolved}" ]] \
    || fail "native package cannot execute or reports an unexpected version"
  # Probe the native protocol with an empty home before replacing the working installation.
  env -u CODEX_HOME HOME="${work_dir}/home" PATH="${work_dir}/application/bin:${PATH}" \
    bash "$(dirname "$0")/configure.sh" \
    || fail "release cannot configure file authentication; choose a supported stable release"
  log "installing verified native Codex ${resolved} to ${APPLICATION_DIR}"
  rm --recursive --force "${APPLICATION_DIR}"
  mv "${work_dir}/application" "${APPLICATION_DIR}"
  chmod 0755 "${APPLICATION_DIR}"
}

install_runtime() {
  local remote_user remote_home
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  log "preparing ${remote_home}/.codex and creation-time helpers for ${STATE_DIR}"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  install --mode 0755 "$(dirname "$0")/configure.sh" "${HELPER_DIR}/configure"
  rm --force "${HELPER_DIR}/configure.mjs"
  cat >"${CLI_PATH}" <<'WRAPPER'
#!/usr/bin/env bash
umask 077
exec /usr/local/share/codex/bin/codex "$@"
WRAPPER
  chmod 0755 "${CLI_PATH}"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "$(id --group "${remote_user}")" "${STATE_DIR}"
  fi
  if [[ ! -L "${remote_home}/.codex" ]]; then
    ln --symbolic --no-target-directory "${STATE_DIR}" "${remote_home}/.codex"
  fi
}

main() {
  validate_environment
  install_prerequisites
  install_release
  install_runtime
}

main "$@"
