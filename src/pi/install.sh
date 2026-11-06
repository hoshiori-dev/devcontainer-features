#!/usr/bin/env bash
# Installs upstream's native Pi coding agent from its GitHub release archive pi-linux-<arch>.tar.gz, verified against
# the release's SHA256SUMS, to /usr/local/lib/pi, and links /usr/local/bin/pi to its executable. Prepares the private
# state volume at /var/lib/pi and links the remote user's ~/.pi/agent to it. Runs as root at image build time; the
# option `version` arrives as VERSION.
set -euo pipefail

readonly RELEASES_API="https://api.github.com/repos/earendil-works/pi/releases"
readonly DOWNLOAD_URL="https://github.com/earendil-works/pi/releases/download"
readonly MIN_VERSION="1.3.0"
readonly APPLICATION_DIR="/usr/local/lib/pi"
readonly CLI_PATH="/usr/local/bin/pi"
readonly HELPER_DIR="/usr/local/share/pi-feature"
readonly STATE_DIR="/var/lib/pi"
readonly AGENT_DIR="${STATE_DIR}/agent"

VERSION="${VERSION-latest}"

work_dir=""
archive_target=""
remote_user=""
remote_home=""
release=""

log() {
  printf 'pi: %s\n' "$*"
}

fail() {
  printf 'pi: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory, with any replaced installation inside it, on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Succeeds when release $1 is at or above release $2; both are MAJOR.MINOR.PATCH.
version_at_least() {
  local i
  local -a have want
  IFS=. read -r -a have <<<"$1"
  IFS=. read -r -a want <<<"$2"
  for i in 0 1 2; do
    if (( 10#${have[i]} > 10#${want[i]} )); then return 0; fi
    if (( 10#${have[i]} < 10#${want[i]} )); then return 1; fi
  done
}

# Selects the release archive for this system; upstream publishes glibc archives for x86_64 and aarch64 only. Runs
# before VERSION becomes readonly: /etc/os-release assigns it too.
detect_platform() {
  local os_id os_version architecture ldd_output
  [[ "$(uname --kernel-name)" == Linux ]] || fail "unsupported system; Pi's native archives need Linux"
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_version="$(. /etc/os-release && printf '%s\n' "${VERSION_ID:-}")"
  case "${os_id}:${os_version}" in
    debian:12 | ubuntu:24.04) ;;
    *) log "warning: untested distribution ${os_id} ${os_version}; attempting the native archive" ;;
  esac
  architecture="$(uname --machine)"
  case "${architecture}" in
    x86_64) archive_target="x64" ;;
    aarch64) archive_target="arm64" ;;
    *) fail "unsupported architecture ${architecture}; Pi publishes native archives for x86_64 and aarch64" ;;
  esac
  # musl's ldd prints its name and exits non-zero when asked for a version.
  ldd_output="$(ldd --version 2>&1 || true)"
  if [[ -f /etc/alpine-release || "${ldd_output,,}" == *musl* ]]; then
    fail "unsupported C library musl; Pi publishes native archives for glibc only, so use a Debian or Ubuntu image"
  fi
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or an exact stable release such as 1.4.0"
  fi
  if [[ "${VERSION}" != latest ]] && ! version_at_least "${VERSION}" "${MIN_VERSION}"; then
    fail "option version is \"${VERSION}\"; this feature supports Pi ${MIN_VERSION} and newer"
  fi
  readonly VERSION
}

# Fails, changing nothing, when Pi is pointed at another agent directory, when a path the feature creates holds other
# content, or when /usr/local/bin/pi is not this feature's link.
check_paths() {
  local path
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6)}"
  [[ "${remote_home}" == /* && -d "${remote_home}" ]] || fail "remote-user home is unavailable; configure remoteUser"
  # Pi ignores an empty value, so only a non-empty one points it elsewhere.
  [[ -z "${PI_CODING_AGENT_DIR:-}" ]] \
    || fail "PI_CODING_AGENT_DIR is set; remove it so Pi keeps its state in ${AGENT_DIR} through ~/.pi/agent"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] || fail "${STATE_DIR} is not a directory; move it aside"
  path="${remote_home}/.pi/agent"
  if [[ -L "${path}" ]]; then
    [[ "$(readlink "${path}")" == "${AGENT_DIR}" ]] \
      || fail "${path} links elsewhere; preserve it and resolve the mapping manually"
  elif [[ -e "${path}" ]]; then
    fail "${path} already exists; back it up and move it aside before installing this feature"
  elif [[ ( -e "${remote_home}/.pi" || -L "${remote_home}/.pi" ) && ! -d "${remote_home}/.pi" ]]; then
    fail "${remote_home}/.pi is not a directory; move it aside before installing this feature"
  fi
  if [[ -e "${CLI_PATH}" || -L "${CLI_PATH}" ]] && [[ "$(readlink "${CLI_PATH}")" != "${APPLICATION_DIR}/pi" ]]; then
    fail "${CLI_PATH} exists and is not this feature's link; remove the other Pi installation first"
  fi
}

# Installs only the missing download and initialization tools, from the image's configured repositories.
install_prerequisites() {
  local tool missing=false
  for tool in curl jq tar gzip sha256sum mountpoint find getent; do
    if ! command -v "${tool}" >/dev/null; then missing=true; fi
  done
  if [[ "${missing}" == false ]]; then return; fi
  log "installing download and initialization prerequisites"
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes --no-install-recommends ca-certificates curl jq tar gzip coreutils findutils util-linux
    rm --recursive --force /var/lib/apt/lists/*
  elif command -v dnf >/dev/null; then
    dnf install --assumeyes ca-certificates curl jq tar gzip coreutils findutils util-linux
    dnf clean all
  else
    fail "prerequisites are missing; install curl, jq, tar, gzip, coreutils, findutils and util-linux"
  fi
}

# Sets release to the stable release VERSION selects, read from the GitHub releases API, and checks that the release
# publishes the archive for this system and a SHA256SUMS file.
resolve_release() {
  local endpoint tag archive="pi-linux-${archive_target}.tar.gz"
  work_dir="$(mktemp --directory /usr/local/lib/.pi-install.XXXXXX)"
  mkdir "${work_dir}/home" "${work_dir}/home/tmp"
  endpoint="${RELEASES_API}/tags/v${VERSION}"
  if [[ "${VERSION}" == latest ]]; then endpoint="${RELEASES_API}/latest"; fi
  log "resolving release ${VERSION} from ${endpoint}"
  fetch --output "${work_dir}/release.json" "${endpoint}" \
    || fail "cannot read release ${VERSION} from ${endpoint}; select a published stable release and check access to GitHub"
  tag="$(jq --raw-output 'select(.draft == false and .prerelease == false) | .tag_name // empty' \
    "${work_dir}/release.json")" || fail "cannot read the release metadata from ${endpoint}; installation stopped"
  [[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "release ${VERSION} is not a stable MAJOR.MINOR.PATCH release; select a stable release"
  release="${tag#v}"
  [[ "${VERSION}" == latest || "${VERSION}" == "${release}" ]] \
    || fail "the releases API names ${tag} for version ${VERSION}; installation stopped"
  version_at_least "${release}" "${MIN_VERSION}" \
    || fail "the latest release is ${release}, older than ${MIN_VERSION}; select an exact supported release"
  jq --exit-status --arg archive "${archive}" \
    'any(.assets[]; .name == $archive) and any(.assets[]; .name == "SHA256SUMS")' "${work_dir}/release.json" \
    >/dev/null || fail "release ${release} publishes no ${archive} with SHA256SUMS; select another release"
}

# Runs executable $1 with arguments $2... in the temporary home, so no state reaches the remote user or the image.
run_isolated() {
  local home="${work_dir}/home"
  env --unset=PI_CODING_AGENT_DIR --unset=PI_PACKAGE_DIR HOME="${home}" TMPDIR="${home}/tmp" PI_OFFLINE=1 "$@"
}

# Installs the selected release unless /usr/local/bin/pi already links to it. The previous installation is replaced
# only after the new one is verified, and restored when the new one cannot load its bundled files through the link.
install_release() {
  local archive="pi-linux-${archive_target}.tar.gz" base_url sum="" name="" expected="" matches=0 installed=""
  if [[ -L "${CLI_PATH}" ]]; then installed="$(run_isolated "${CLI_PATH}" --version)" || installed=""; fi
  if [[ "${installed}" == "${release}" ]]; then
    log "Pi ${release} is already installed at ${APPLICATION_DIR}"
    return
  fi
  base_url="${DOWNLOAD_URL}/v${release}"
  log "downloading ${base_url}/SHA256SUMS"
  fetch --output "${work_dir}/SHA256SUMS" "${base_url}/SHA256SUMS" \
    || fail "cannot download SHA256SUMS of release ${release}; installation stopped"
  # The second test keeps a last line without a trailing newline.
  while read -r sum name || [[ -n "${sum}" ]]; do
    if [[ "${name}" == "${archive}" ]]; then
      expected="${sum}"
      matches=$((matches + 1))
    fi
  done <"${work_dir}/SHA256SUMS"
  [[ "${matches}" == 1 && "${expected}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "SHA256SUMS of release ${release} lists no single checksum for ${archive}; installation stopped"
  log "downloading ${base_url}/${archive}"
  fetch --output "${work_dir}/${archive}" "${base_url}/${archive}" \
    || fail "cannot download ${base_url}/${archive}; check access to GitHub"
  printf '%s  %s\n' "${expected}" "${work_dir}/${archive}" | sha256sum --check --quiet \
    || fail "${archive} of release ${release} does not match its SHA256SUMS; installation stopped"
  mkdir "${work_dir}/staged"
  tar --extract --gzip --no-same-owner --file "${work_dir}/${archive}" --directory "${work_dir}/staged" \
    || fail "cannot extract ${archive} of release ${release}"
  [[ -f "${work_dir}/staged/pi/pi" && ! -L "${work_dir}/staged/pi/pi" ]] \
    || fail "${archive} of release ${release} holds no pi/pi executable; installation stopped"
  chmod --recursive u=rwX,go=rX "${work_dir}/staged/pi"
  [[ "$(run_isolated "${work_dir}/staged/pi/pi" --version)" == "${release}" ]] \
    || fail "the verified executable cannot run or reports another version; ${CLI_PATH} is unchanged"
  log "installing Pi ${release} to ${APPLICATION_DIR} and linking ${CLI_PATH} to it"
  if [[ -e "${APPLICATION_DIR}" || -L "${APPLICATION_DIR}" ]]; then mv "${APPLICATION_DIR}" "${work_dir}/previous"; fi
  mv "${work_dir}/staged/pi" "${APPLICATION_DIR}"
  ln --symbolic --force --no-target-directory "${APPLICATION_DIR}/pi" "${CLI_PATH}"
  # A Pi executable that cannot find package.json beside it reports version 0.0.0.
  if [[ "$(run_isolated "${CLI_PATH}" --version)" != "${release}" ]]; then
    rm --recursive --force "${APPLICATION_DIR}"
    if [[ -e "${work_dir}/previous" || -L "${work_dir}/previous" ]]; then
      mv "${work_dir}/previous" "${APPLICATION_DIR}"
    else
      rm --force "${CLI_PATH}"
    fi
    fail "${CLI_PATH} cannot load Pi's bundled files through its link; the previous installation is restored"
  fi
}

prepare_state() {
  local group
  group="$(id --group "${remote_user}")"
  log "installing the creation-time initializer to ${HELPER_DIR}/initialize"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"
  log "preparing ${STATE_DIR} and linking ${remote_home}/.pi/agent of ${remote_user} to ${AGENT_DIR}"
  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_DIR}"
  fi
  if [[ ! -e "${AGENT_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${AGENT_DIR}"
  fi
  if [[ ! -L "${remote_home}/.pi/agent" ]]; then
    if [[ ! -e "${remote_home}/.pi" ]]; then
      install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${remote_home}/.pi"
    fi
    ln --symbolic --no-target-directory "${AGENT_DIR}" "${remote_home}/.pi/agent"
  fi
}

main() {
  detect_platform
  validate_options
  check_paths
  install_prerequisites
  trap cleanup EXIT
  resolve_release
  install_release
  prepare_state
}

main "$@"
