#!/usr/bin/env bash
# Installs the Google Antigravity CLI from the archive its official platform manifest names, verified against the
# manifest's SHA-512, to /usr/local/share/antigravity/agy with an `agy` launcher in /usr/local/bin, and links the
# remote user's Antigravity state directories to /var/lib/antigravity. Runs as root at image build time; it takes no
# options.
set -euo pipefail

readonly MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests"
readonly ARCHIVE_PREFIX="https://storage.googleapis.com/antigravity-public/antigravity-cli/"
readonly APPLICATION_DIR="/usr/local/share/antigravity"
readonly APPLICATION_PATH="/usr/local/share/antigravity/agy"
readonly CLI_PATH="/usr/local/bin/agy"
readonly HELPER_DIR="/usr/local/share/antigravity-feature"
readonly STATE_DIR="/var/lib/antigravity"
# Each mapping is <home-relative link path>:<state subdirectory it points to>.
readonly MAPPINGS=(".gemini/antigravity-cli:cli" ".gemini/config:gemini-config" ".config/antigravity:plugin-secrets")

work_dir=""
platform=""
remote_user=""
remote_home=""

log() {
  printf 'antigravity: %s\n' "$*"
}

fail() {
  printf 'antigravity: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staging directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Selects the manifest platform the way Google's installer does, warns on an untested distribution, and checks the
# remote user's home and the state paths before anything changes.
validate_environment() {
  local os_id os_version architecture mapping link_path
  [[ "$(uname --kernel-name)" == Linux ]] || fail "unsupported system; the Antigravity CLI is published for Linux only"
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64) platform="linux_amd64" ;;
    aarch64 | arm64) platform="linux_arm64" ;;
    *) fail "unsupported architecture ${architecture}; no official Antigravity CLI archive covers it" ;;
  esac
  if [[ -f /lib/libc.musl-x86_64.so.1 || -f /lib/libc.musl-aarch64.so.1 ]]; then
    platform="${platform}_musl"
  elif command -v ldd >/dev/null && [[ "$(ldd /bin/ls 2>&1 || true)" == *musl* ]]; then
    platform="${platform}_musl"
  fi
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s\n' "${VERSION_ID:-}")"
  case "${os_id}:${os_version}" in
    debian:12 | ubuntu:24.04) ;;
    *) log "warning: untested distribution ${os_id} ${os_version}; attempting the official ${platform} archive" ;;
  esac
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  [[ "${remote_home}" == /* && -d "${remote_home}" ]] || fail "remote-user home is unavailable; configure remoteUser"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] \
    || fail "${STATE_DIR} is not a directory; preserve it and resolve the mount path"
  for mapping in "${MAPPINGS[@]}"; do
    link_path="${remote_home}/${mapping%%:*}"
    if [[ -L "${link_path}" ]]; then
      [[ "$(readlink --canonicalize-missing "${link_path}")" == "${STATE_DIR}/${mapping#*:}" ]] \
        || fail "existing ${link_path} link points elsewhere; preserve it and resolve the mapping manually"
    elif [[ -e "${link_path}" ]]; then
      fail "existing ${link_path} conflicts; preserve it and migrate it explicitly before enabling this feature"
    fi
  done
}

# Installs only missing download and initialization tools, from the image's configured repositories.
install_prerequisites() {
  local tool
  local missing=false
  for tool in curl jq tar gzip sha512sum mountpoint find getent; do
    if ! command -v "${tool}" >/dev/null; then missing=true; fi
  done
  if [[ "${missing}" == false ]]; then return; fi
  log "installing download and initialization prerequisites"
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
  else
    fail "prerequisites are missing; install curl, jq, tar, gzip, coreutils, findutils and util-linux"
  fi
}

# Resolves the current manifest, verifies the archive it names, runs the staged executable in an isolated home, and
# only then replaces the installed CLI. An installed CLI that already reports the manifest's version stays in place.
install_release() {
  local version url digest installed=""
  work_dir="$(mktemp --directory /usr/local/share/.antigravity-install.XXXXXX)"
  mkdir "${work_dir}/home" "${work_dir}/payload"
  log "resolving the current Antigravity CLI from ${MANIFEST_URL}/${platform}.json"
  fetch --output "${work_dir}/manifest.json" "${MANIFEST_URL}/${platform}.json" \
    || fail "cannot download the ${platform} platform manifest; check access to the official manifest service"
  version="$(jq --raw-output '.version | strings' "${work_dir}/manifest.json")" \
    || fail "the platform manifest is not valid JSON"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "the platform manifest names no valid version"
  url="$(jq --raw-output '.url | strings' "${work_dir}/manifest.json")"
  if [[ "${url}" != "${ARCHIVE_PREFIX}"* || ! "${url}" =~ ^[A-Za-z0-9:/._-]+$ || "${url}" == *..* ]]; then
    fail "the manifest's archive URL is outside the allowed distribution prefix ${ARCHIVE_PREFIX}"
  fi
  digest="$(jq --raw-output '.sha512 | strings' "${work_dir}/manifest.json")"
  [[ "${digest}" =~ ^[0-9a-f]{128}$ ]] || fail "the platform manifest has no valid SHA-512 digest"
  if [[ -x "${APPLICATION_PATH}" ]]; then
    installed="$(HOME="${work_dir}/home" "${APPLICATION_PATH}" --version)" || installed=""
  fi
  if [[ "${installed}" == "${version}" ]]; then
    log "Antigravity CLI ${version} is already installed at ${APPLICATION_PATH}"
    return
  fi
  log "downloading ${url}"
  fetch --output "${work_dir}/archive.tar.gz" "${url}" || fail "cannot download the archive the manifest names"
  printf '%s  %s\n' "${digest}" "${work_dir}/archive.tar.gz" | sha512sum --check --quiet \
    || fail "the archive does not match the manifest's SHA-512 digest"
  tar --extract --gzip --no-same-owner --file "${work_dir}/archive.tar.gz" --directory "${work_dir}/payload"
  [[ -f "${work_dir}/payload/antigravity" && ! -L "${work_dir}/payload/antigravity" ]] \
    || fail "the verified archive holds no antigravity executable"
  chmod 0755 "${work_dir}/payload/antigravity"
  [[ "$(HOME="${work_dir}/home" "${work_dir}/payload/antigravity" --version)" == "${version}" ]] \
    || fail "the verified executable cannot run or reports a version other than ${version}"
  log "installing Antigravity CLI ${version} to ${APPLICATION_PATH}"
  install --directory --mode 0755 "${APPLICATION_DIR}"
  mv "${work_dir}/payload/antigravity" "${APPLICATION_DIR}/.agy.new"
  mv --force "${APPLICATION_DIR}/.agy.new" "${APPLICATION_PATH}"
}

# Installs the launcher and the creation-time initializer, and prepares the state root and the home links the
# initializer later verifies once the volume is mounted.
install_runtime() {
  local group mapping link_path target parent
  group="$(id --group "${remote_user}")"
  log "installing ${CLI_PATH} and ${HELPER_DIR}/initialize"
  cat >"${CLI_PATH}" <<'LAUNCHER'
#!/bin/sh
# Starts the Antigravity CLI with a private umask, so new state files are readable by their owner only.
umask 077
exec /usr/local/share/antigravity/agy "$@"
LAUNCHER
  chmod 0755 "${CLI_PATH}"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  log "preparing ${STATE_DIR} and the Antigravity state links in ${remote_home}"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_DIR}"
  fi
  for mapping in "${MAPPINGS[@]}"; do
    target="${STATE_DIR}/${mapping#*:}"
    if [[ ! -e "${target}" ]]; then
      install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${target}"
    fi
    link_path="${remote_home}/${mapping%%:*}"
    parent="$(dirname "${link_path}")"
    if [[ ! -e "${parent}" ]]; then
      install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${parent}"
    fi
    if [[ ! -L "${link_path}" ]]; then
      ln --symbolic --no-target-directory "${target}" "${link_path}"
      chown --no-dereference "${remote_user}:${group}" "${link_path}"
    fi
  done
}

main() {
  validate_environment
  install_prerequisites
  trap cleanup EXIT
  install_release
  install_runtime
}

main "$@"
