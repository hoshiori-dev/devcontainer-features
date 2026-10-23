#!/usr/bin/env bash
# Installs official Claude Code native binaries with a pinned manifest-signing key and SHA-256 verification.
# to /usr/local/share/claude-code. Runs as root at image build time; option version arrives as VERSION.
set -euo pipefail

readonly RELEASE_API="https://downloads.claude.ai/claude-code-releases"
readonly SIGNING_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"
readonly SIGNING_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
readonly APPLICATION_DIR="/usr/local/share/claude-code"
readonly CLI_PATH="/usr/local/bin/claude"
readonly HELPER_DIR="/usr/local/share/claude-code-feature"
readonly STATE_DIR="/var/lib/claude-code"
VERSION="${VERSION-latest}"
work_dir=""
platform_target=""

log() { printf 'claude-code: %s\n' "$*"; }
fail() { printf 'claude-code: error: %s\n' "$*" >&2; exit 1; }

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
    x86_64) platform_target="linux-x64" ;;
    aarch64) platform_target="linux-arm64" ;;
    *) fail "unsupported architecture ${architecture}; no matching official native package" ;;
  esac
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid version; use latest or an exact stable MAJOR.MINOR.PATCH release"
  fi
  [[ "${VERSION}" == latest || "$(printf '%s\n' 2.1.89 "${VERSION}" | sort --version-sort | head --lines=1)" == 2.1.89 ]] \
    || fail "unsupported release; use 2.1.89 or newer"
  case "$(ldd --version 2>&1 || true)" in *musl*) platform_target="${platform_target}-musl" ;; esac
  readonly VERSION
  [[ "${CLAUDE_CONFIG_DIR+x}" != x ]] || fail "CLAUDE_CONFIG_DIR is configured; remove the override before using this feature"
  home_path="${_REMOTE_USER_HOME:-$(getent passwd "${_REMOTE_USER:-root}" | cut --delimiter=: --fields=6)}"
  [[ -d "${home_path}" && "${home_path}" == /* ]] || fail "remote-user home is unavailable; configure remoteUser"
  [[ ! -e "${home_path}/.claude.json" && ! -L "${home_path}/.claude.json" ]] \
    || fail "existing .claude.json is outside the mapped home; preserve it and migrate it explicitly"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory; preserve it and resolve the mount path"
  if [[ -L "${home_path}/.claude" ]]; then
    [[ "$(readlink --canonicalize-existing "${home_path}/.claude")" == "${STATE_DIR}" ]] \
      || fail "existing .claude link conflicts; preserve it and resolve the mapping manually"
  elif [[ -e "${home_path}/.claude" ]]; then
    fail "existing .claude content conflicts; preserve it and migrate it explicitly before enabling this feature"
  fi
}

# Bootstrap only missing native-package tools, using the image's configured repositories and verification.
install_prerequisites() {
  local tool missing=false
  for tool in curl jq gpg sha256sum mountpoint find getent; do
    if ! command -v "${tool}" >/dev/null; then missing=true; fi
  done
  if [[ "${missing}" == false ]]; then return; fi
  log "installing native-package download and initialization prerequisites"
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes --no-install-recommends ca-certificates curl jq gnupg tar gzip coreutils findutils util-linux
    rm --recursive --force /var/lib/apt/lists/*
  elif command -v apk >/dev/null; then
    apk add --no-cache ca-certificates curl jq gnupg tar gzip coreutils findutils util-linux musl-utils
  elif command -v dnf >/dev/null; then
    dnf install --assumeyes ca-certificates curl jq gnupg tar gzip coreutils findutils util-linux
    dnf clean all
  elif command -v microdnf >/dev/null; then
    microdnf install --assumeyes ca-certificates curl jq gnupg tar gzip coreutils findutils util-linux
    microdnf clean all
  elif command -v yum >/dev/null; then
    yum install --assumeyes ca-certificates curl jq gnupg tar gzip coreutils findutils util-linux
    yum clean all
  else
    fail "native-package prerequisites are missing; install curl, jq, tar, gzip, coreutils, findutils and util-linux"
  fi
}

fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

install_release() {
  local resolved expected fingerprint installed=""
  work_dir="$(mktemp --directory /usr/local/share/.claude-code-install.XXXXXX)"
  trap cleanup EXIT
  mkdir --parents "${work_dir}/home" "${work_dir}/gnupg"
  chmod 0700 "${work_dir}/gnupg"
  resolved="${VERSION}"
  if [[ "${resolved}" == latest ]]; then
    log "resolving the official native Claude Code release"
    resolved="$(fetch "${RELEASE_API}/latest")" || fail "cannot resolve latest; check official release access"
  fi
  [[ "${resolved}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid release metadata; select a stable release"
  [[ "$(printf '%s\n' 2.1.89 "${resolved}" | sort --version-sort | head --lines=1)" == 2.1.89 ]] \
    || fail "unsupported release; select 2.1.89 or newer"
  log "verifying the signed native release ${resolved} from ${RELEASE_API}"
  fetch --output "${work_dir}/manifest.json" "${RELEASE_API}/${resolved}/manifest.json" \
    || fail "cannot fetch release manifest; check version and network access"
  fetch --output "${work_dir}/manifest.sig" "${RELEASE_API}/${resolved}/manifest.json.sig" \
    || fail "cannot fetch required manifest signature; select a signed release"
  fetch --output "${work_dir}/key.asc" "${SIGNING_KEY_URL}" || fail "cannot fetch signing key; check official access"
  fingerprint="$(gpg --batch --homedir "${work_dir}/gnupg" --with-colons --show-keys "${work_dir}/key.asc" \
    | awk -F: '$1 == "fpr" {print $10; exit}')" \
    || fail "cannot inspect signing key; check the upstream key format"
  [[ "$(gpg --batch --homedir "${work_dir}/gnupg" --with-colons --show-keys "${work_dir}/key.asc" \
    | awk -F: '$1 == "pub" {n++} END {print n}')" == 1 ]] || fail "signing key bundle is ambiguous; inspect upstream keys"
  [[ "${fingerprint}" == "${SIGNING_FINGERPRINT}" ]] || fail "unexpected signing key; inspect the official key rotation"
  gpg --batch --homedir "${work_dir}/gnupg" --import "${work_dir}/key.asc"
  gpg --batch --homedir "${work_dir}/gnupg" --verify "${work_dir}/manifest.sig" "${work_dir}/manifest.json" \
    || fail "manifest signature verification failed; do not use this payload"
  expected="$(jq --exit-status --raw-output --arg version "${resolved}" --arg target "${platform_target}" \
    'select(.version == $version) | .platforms[$target] | select(.binary == "claude") | .checksum' \
    "${work_dir}/manifest.json")" || fail "unsupported target or release manifest; select a covered target"
  [[ "${expected}" =~ ^[a-fA-F0-9]{64}$ ]] || fail "missing valid checksum; select a verified release"
  if [[ -x "${APPLICATION_DIR}/claude" ]]; then
    installed="$(env -u CLAUDE_CONFIG_DIR HOME="${work_dir}/home" "${APPLICATION_DIR}/claude" --version)" || installed=""
  fi
  if [[ "${installed}" == "${resolved} (Claude Code)" ]]; then return; fi
  fetch --output "${work_dir}/claude" "${RELEASE_API}/${resolved}/${platform_target}/claude" \
    || fail "cannot download official binary; check platform and release access"
  printf '%s  %s\n' "${expected}" "${work_dir}/claude" | sha256sum --check --quiet \
    || fail "binary checksum verification failed; do not execute this payload"
  chmod 0755 "${work_dir}/claude"
  [[ "$(env -u CLAUDE_CONFIG_DIR HOME="${work_dir}/home" "${work_dir}/claude" --version)" == "${resolved} (Claude Code)" ]] \
    || fail "native binary cannot execute or reports an unexpected version"
  log "installing verified Claude Code ${resolved} to ${APPLICATION_DIR}"
  install --directory --mode 0755 "${APPLICATION_DIR}"
  mv --force "${work_dir}/claude" "${APPLICATION_DIR}/claude"
}

install_runtime() {
  local remote_user remote_home
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  log "preparing ${remote_home}/.claude and creation-time helpers for ${STATE_DIR}"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  cat >"${CLI_PATH}" <<'WRAPPER'
#!/usr/bin/env bash
umask 077
[[ "${CLAUDE_CONFIG_DIR+x}" != x ]] || { printf 'claude-code: error: remove the CLAUDE_CONFIG_DIR override\n' >&2; exit 1; }
export CLAUDE_CONFIG_DIR=/var/lib/claude-code
export DISABLE_AUTOUPDATER=1
exec /usr/local/share/claude-code/claude "$@"
WRAPPER
  chmod 0755 "${CLI_PATH}"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "$(id --group "${remote_user}")" "${STATE_DIR}"
  fi
  if [[ ! -L "${remote_home}/.claude" ]]; then
    ln --symbolic --no-target-directory "${STATE_DIR}" "${remote_home}/.claude"
  fi
}

main() {
  validate_environment
  install_prerequisites
  install_release
  install_runtime
}

main "$@"
