#!/usr/bin/env bash
# Installs upstream's native OpenCode v2 executable from the platform package @opencode/cli-<target> on the npm
# registry, verified against the registry's SHA-512 integrity, to /usr/local/bin/opencode. Prepares the private state
# volume at /var/lib/opencode and links the remote user's OpenCode XDG directories to it. Runs as root at image build
# time; the option `version` arrives as VERSION.
set -euo pipefail

readonly REGISTRY_URL="https://registry.npmjs.org"
readonly CHANNEL_TAGS_URL="${REGISTRY_URL}/-/package/@opencode%2fcli/dist-tags"
readonly CLI_PATH="/usr/local/bin/opencode"
readonly HELPER_DIR="/usr/local/share/opencode-feature"
readonly STATE_DIR="/var/lib/opencode"
readonly STATE_KINDS=(data config state cache)

VERSION="${VERSION-latest}"

work_dir=""
package_target=""
remote_user=""
remote_home=""
release=""

log() {
  printf 'opencode: %s\n' "$*"
}

fail() {
  printf 'opencode: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Prints the default XDG root, relative to the home directory, that holds OpenCode's directory of kind $1.
default_root() {
  case "$1" in
    data) printf '.local/share\n' ;;
    config) printf '.config\n' ;;
    state) printf '.local/state\n' ;;
    cache) printf '.cache\n' ;;
  esac
}

# Selects the platform package as upstream's native installer does. Runs before VERSION becomes readonly:
# /etc/os-release assigns it too.
detect_platform() {
  local os_id os_version architecture ldd_output
  [[ "$(uname --kernel-name)" == Linux ]] || fail "unsupported system; OpenCode's native packages need Linux"
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s\n' "${VERSION_ID:-}")"
  case "${os_id}:${os_version}" in
    debian:12 | ubuntu:24.04) ;;
    *) log "warning: untested distribution ${os_id} ${os_version}; attempting the native package" ;;
  esac
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64) package_target="linux-x64" ;;
    aarch64) package_target="linux-arm64" ;;
    *) fail "unsupported architecture ${architecture}; OpenCode publishes native packages for x86_64 and aarch64" ;;
  esac
  if [[ "${package_target}" == linux-x64 ]] && ! grep --quiet --word-regexp --ignore-case avx2 /proc/cpuinfo; then
    package_target+="-baseline"
  fi
  # musl's ldd prints its name and exits non-zero when asked for a version.
  ldd_output="$(ldd --version 2>&1 || true)"
  if [[ -f /etc/alpine-release || "${ldd_output,,}" == *musl* ]]; then package_target+="-musl"; fi
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or an exact stable release such as 2.1.3"
  fi
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^2\. ]]; then
    fail "option version is \"${VERSION}\"; this feature supports stable OpenCode 2.x releases only"
  fi
  readonly VERSION
}

# Fails unless every OpenCode directory under the remote user's default XDG roots is absent or links to the volume.
check_state_paths() {
  local kind root path
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  [[ "${remote_home}" == /* && -d "${remote_home}" ]] || fail "remote-user home is unavailable; configure remoteUser"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory; move it aside"
  for kind in "${STATE_KINDS[@]}"; do
    root="${remote_home}/$(default_root "${kind}")"
    path="${root}/opencode"
    if [[ -L "${path}" ]]; then
      [[ "$(readlink "${path}")" == "${STATE_DIR}/${kind}" ]] \
        || fail "${path} links elsewhere; preserve it and resolve the mapping manually"
    elif [[ -e "${path}" ]]; then
      fail "${path} already exists; back it up and move it aside before installing this feature"
    elif [[ -e "${root}" && ! -d "${root}" ]]; then
      fail "${root} is not a directory; move it aside before installing this feature"
    fi
  done
}

# Installs only the missing download tools, from the image's configured repositories.
install_prerequisites() {
  local tool missing=false
  for tool in curl jq tar gzip sha512sum base64 od mountpoint find getent; do
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

# Sets release to the one VERSION selects; latest is the @opencode/cli dist-tag, accepted only as a stable 2.x release.
resolve_release() {
  local tags latest
  if [[ "${VERSION}" != latest ]]; then
    release="${VERSION}"
    return
  fi
  log "resolving the latest release from ${CHANNEL_TAGS_URL}"
  tags="$(fetch "${CHANNEL_TAGS_URL}")" || fail "cannot read the @opencode/cli dist-tags; check access to the registry"
  latest="$(jq --raw-output '.latest // empty' <<<"${tags}")"
  [[ "${latest}" =~ ^2\.[0-9]+\.[0-9]+$ ]] \
    || fail "the latest dist-tag names \"${latest}\", not a stable 2.x release; select an exact version"
  release="${latest}"
}

# Installs the selected release unless /usr/local/bin/opencode already reports it.
install_release() {
  local package metadata tarball integrity expected actual installed=""
  work_dir="$(mktemp --directory /usr/local/share/.opencode-install.XXXXXX)"
  mkdir "${work_dir}/home"
  if [[ -x "${CLI_PATH}" ]]; then installed="$(run_isolated "${CLI_PATH}" --version)" || installed=""; fi
  if [[ "${installed}" == "opencode v${release}" ]]; then
    log "OpenCode ${release} is already installed at ${CLI_PATH}"
    return
  fi
  package="@opencode/cli-${package_target}"
  log "reading the metadata of ${package} ${release} from ${REGISTRY_URL}"
  metadata="$(fetch "${REGISTRY_URL}/@opencode%2fcli-${package_target}/${release}")" \
    || fail "release ${release} is unavailable for ${package_target}; select a published 2.x release"
  tarball="$(jq --raw-output '.dist.tarball // empty' <<<"${metadata}")"
  integrity="$(jq --raw-output '.dist.integrity // empty' <<<"${metadata}")"
  [[ "${tarball}" == "${REGISTRY_URL}/${package}/-/cli-${package_target}-${release}.tgz" ]] \
    || fail "the registry names an unexpected tarball for ${package} ${release}; installation stopped"
  [[ "${integrity}" =~ ^sha512-[A-Za-z0-9+/]{86}==$ ]] \
    || fail "the registry publishes no SHA-512 integrity for ${package} ${release}; installation stopped"
  expected="$(base64 --decode <<<"${integrity#sha512-}" | od --address-radix=n --format=x1 --output-duplicates \
    | tr --delete ' \n')"
  log "downloading ${tarball}"
  fetch --output "${work_dir}/package.tgz" "${tarball}" || fail "cannot download ${tarball}; check access to the registry"
  actual="$(sha512sum "${work_dir}/package.tgz" | cut --delimiter=' ' --fields=1)"
  [[ "${actual}" == "${expected}" ]] || fail "${package} ${release} does not match its published integrity"
  tar --extract --gzip --no-same-owner --file "${work_dir}/package.tgz" --directory "${work_dir}" package/bin/opencode \
    || fail "${package} ${release} holds no package/bin/opencode"
  chmod 0755 "${work_dir}/package/bin/opencode"
  [[ "$(run_isolated "${work_dir}/package/bin/opencode" --version)" == "opencode v${release}" ]] \
    || fail "the verified executable cannot run or reports another version; ${CLI_PATH} is unchanged"
  log "installing OpenCode ${release} to ${CLI_PATH}"
  mv --force "${work_dir}/package/bin/opencode" "${CLI_PATH}"
}

# Runs executable $1 with arguments $2... in the temporary home, so no state reaches the remote user or the image.
run_isolated() {
  local home="${work_dir}/home"
  env HOME="${home}" XDG_DATA_HOME="${home}/data" XDG_CONFIG_HOME="${home}/config" XDG_STATE_HOME="${home}/state" \
    XDG_CACHE_HOME="${home}/cache" "$@"
}

# Creates directory $1 and its missing parents below the remote user's home, owned by the remote user.
make_user_dir() {
  local relative="${1#"${remote_home}"/}" part dir="${remote_home}"
  local -a parts
  IFS=/ read -r -a parts <<<"${relative}"
  for part in "${parts[@]}"; do
    dir+="/${part}"
    if [[ ! -e "${dir}" ]]; then
      install --directory --owner "${remote_user}" --group "$(id --group "${remote_user}")" "${dir}"
    fi
  done
}

prepare_state() {
  local kind root group
  group="$(id --group "${remote_user}")"
  log "installing the creation-time initializer to ${HELPER_DIR}/initialize"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  log "preparing ${STATE_DIR} and linking the OpenCode XDG directories of ${remote_user} to it"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_DIR}"
  fi
  for kind in "${STATE_KINDS[@]}"; do
    if [[ ! -e "${STATE_DIR}/${kind}" ]]; then
      install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_DIR}/${kind}"
    fi
    root="${remote_home}/$(default_root "${kind}")"
    if [[ ! -L "${root}/opencode" ]]; then
      make_user_dir "${root}"
      ln --symbolic --no-target-directory "${STATE_DIR}/${kind}" "${root}/opencode"
    fi
  done
}

main() {
  detect_platform
  validate_options
  check_state_paths
  install_prerequisites
  trap cleanup EXIT
  resolve_release
  install_release
  prepare_state
}

main "$@"
