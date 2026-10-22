#!/usr/bin/env bash
# Installs @openai/codex from the official npm registry to /usr/local/share/codex, with a CLI wrapper at
# /usr/local/bin/codex. Runs as root at image build time; option version arrives as VERSION.
set -euo pipefail

readonly REGISTRY="https://registry.npmjs.org/"
readonly APPLICATION_DIR="/usr/local/share/codex"
readonly CLI_PATH="/usr/local/bin/codex"
readonly HELPER_DIR="/usr/local/share/codex-feature"
readonly STATE_DIR="/var/lib/codex"
VERSION="${VERSION-latest}"
work_dir=""

log() { printf 'codex: %s\n' "$*"; }
fail() { printf 'codex: error: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

validate_environment() {
  local os_id os_version architecture home_path
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
  case "${os_id}:${os_version}" in
    debian:12 | ubuntu:24.04) ;;
    *) fail "unsupported distribution; use Debian 12 or Ubuntu 24.04" ;;
  esac
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64 | aarch64) ;;
    *) fail "unsupported architecture; use amd64 or arm64" ;;
  esac
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid version; use latest or an exact stable MAJOR.MINOR.PATCH release"
  fi
  readonly VERSION
  [[ "${CODEX_HOME+x}" != x ]] || fail "CODEX_HOME is configured; remove the override before using this feature"
  command -v npm >/dev/null || fail "npm is missing; install the declared Node 24 feature dependency"
  [[ "$(node --print 'process.versions.node.split(".")[0]')" == 24 ]] \
    || fail "Node 24 is required; use the declared dependency"
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

install_release() {
  local resolved installed
  work_dir="$(mktemp --directory)"
  trap cleanup EXIT
  log "resolving @openai/codex@${VERSION} from ${REGISTRY}"
  npm view "@openai/codex@${VERSION}" version --json --registry "${REGISTRY}" \
    --@openai:registry="${REGISTRY}" --strict-ssl=true >"${work_dir}/version.json" \
    || fail "cannot resolve release; check the version and registry access"
  resolved="$(node --input-type=module - "${work_dir}/version.json" <<'JS'
import { readFileSync } from 'node:fs';
const version = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (typeof version !== 'string' || !/^\d+\.\d+\.\d+$/.test(version)) process.exit(1);
console.log(version);
JS
  )" || fail "the registry selection is not a stable release; select an exact stable version"
  installed=""
  if [[ -f "${APPLICATION_DIR}/node_modules/@openai/codex/package.json" ]]; then
    installed="$(node --print "require('${APPLICATION_DIR}/node_modules/@openai/codex/package.json').version")"
  fi
  if [[ "${installed}" != "${resolved}" || ! -x "${APPLICATION_DIR}/node_modules/.bin/codex" ]]; then
    log "installing verified npm packages for Codex ${resolved} to ${APPLICATION_DIR}"
    npm install --prefix "${work_dir}/application" --registry "${REGISTRY}" --@openai:registry="${REGISTRY}" \
      --strict-ssl=true --ignore-scripts --no-audit --no-fund --save-exact "@openai/codex@${resolved}" \
      || fail "npm installation or integrity verification failed; check registry access and retry"
    mkdir --parents "${work_dir}/home"
    # Probe the native protocol before replacing the CLI, with an empty home and no account data.
    env -u CODEX_HOME HOME="${work_dir}/home" PATH="${work_dir}/application/node_modules/.bin:${PATH}" \
      node "$(dirname "$0")/configure.mjs" \
      || fail "release cannot configure file authentication; choose a supported stable release"
    rm --recursive --force "${APPLICATION_DIR}"
    mv "${work_dir}/application" "${APPLICATION_DIR}"
    chmod 0755 "${APPLICATION_DIR}"
  fi
}

install_runtime() {
  local remote_user remote_home
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  log "preparing ${remote_home}/.codex and creation-time helpers for ${STATE_DIR}"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  install --mode 0644 "$(dirname "$0")/configure.mjs" "${HELPER_DIR}/configure.mjs"
  cat >"${CLI_PATH}" <<'WRAPPER'
#!/usr/bin/env bash
umask 077
exec /usr/local/share/codex/node_modules/.bin/codex "$@"
WRAPPER
  chmod 0755 "${CLI_PATH}"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "$(id --group "${remote_user}")" "${STATE_DIR}"
  fi
  if [[ ! -L "${remote_home}/.codex" ]]; then ln --symbolic "${STATE_DIR}" "${remote_home}/.codex"; fi
}

main() {
  validate_environment
  install_release
  install_runtime
}

main "$@"
