#!/usr/bin/env bash
# Installs Incus from the Zabbly package repository (https://pkgs.zabbly.com/incus/<channel>), which upstream's
# installation guide names for Debian and Ubuntu: the package incus-base (containers only) or, with the option vm,
# incus (with virtual machine support), at the newest version of the chosen channel. The repository's signing key is
# fetched from https://pkgs.zabbly.com/key.asc and accepted only by its pinned fingerprint; it is installed as
# /etc/apt/keyrings/zabbly.asc, and the repository is defined in /etc/apt/sources.list.d/zabbly-incus.sources. curl,
# CA certificates, and GnuPG are installed from the image's repositories when missing, and
# systemd-standalone-sysusers where the image has no systemd-sysusers and the distribution ships that package, so
# that the Zabbly packages do not pull systemd in, and nftables, one of the two packet filter tools the Zabbly
# packages depend on and the one the daemon calls. Adds the remote user to the incus-admin group, records the
# settings in /usr/local/share/incus-feature/settings, and installs the two start scripts beside it: start.sh, the
# feature's entrypoint, and check.sh, its postStartCommand. Downloads nothing else.
# Runs as root at image build time; options arrive as environment variables:
#   channel: CHANNEL
#   vm: VM
#   initialize: INITIALIZE
set -euo pipefail

readonly KEY_URL="https://pkgs.zabbly.com/key.asc"
# The primary fingerprint of the Zabbly signing key (openspec/specs/incus/spec.md, "Zabbly signing key"). The fetched
# file must hold this key and no other.
readonly SIGNING_FINGERPRINT="4EFC590696CB15B87C73A3AD82CC8797C838DCFD"
# The first line of an armored OpenPGP public key block.
readonly KEY_BLOCK_BEGIN="-----BEGIN PGP PUBLIC KEY BLOCK-----"
readonly REPOSITORY_URL="https://pkgs.zabbly.com/incus"
readonly KEYRINGS_DIR="/etc/apt/keyrings"
readonly KEY_FILE="/etc/apt/keyrings/zabbly.asc"
readonly SOURCES_FILE="/etc/apt/sources.list.d/zabbly-incus.sources"
readonly SHARE_DIR="/usr/local/share/incus-feature"
readonly SETTINGS_FILE="/usr/local/share/incus-feature/settings"
readonly START_SCRIPT="/usr/local/share/incus-feature/start.sh"
readonly CHECK_SCRIPT="/usr/local/share/incus-feature/check.sh"
readonly LOG_DIR="/var/log/incus"
# The group whose members control the daemon through its socket; the Zabbly packages create it.
readonly ADMIN_GROUP="incus-admin"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

export DEBIAN_FRONTEND=noninteractive

CHANNEL="${CHANNEL-stable}"
VM="${VM-false}"
INITIALIZE="${INITIALIZE-minimal}"
# The remote user, which the Dev Container tooling names in _REMOTE_USER; root when it names none.
readonly REMOTE_USER_NAME="${_REMOTE_USER:-root}"

os_id=""
# The release's codename, which names the repository's suite.
codename=""
# The image's architecture as dpkg names it: amd64 or arm64.
arch=""
work_dir=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf 'incus: %s\n' "$*"
}

fail() {
  printf 'incus: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl over HTTPS only, on every hop including redirects, with failing HTTP statuses as errors. --retry 3
# handles a known failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

validate_options() {
  if [[ ! "${CHANNEL}" =~ ^(stable|lts-7\.0|lts-6\.0)$ ]]; then
    fail "option channel is \"${CHANNEL}\"; use stable, lts-7.0, or lts-6.0"
  fi
  if [[ ! "${VM}" =~ ^(true|false)$ ]]; then
    fail "option vm is \"${VM}\"; use true or false"
  fi
  if [[ ! "${INITIALIZE}" =~ ^(minimal|none)$ ]]; then
    fail "option initialize is \"${INITIALIZE}\"; use minimal or none"
  fi
  readonly CHANNEL VM INITIALIZE
}

# Sets os_id, codename, and arch; fails on an unsupported distribution or architecture before anything changes.
detect_platform() {
  local machine
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in
    debian | ubuntu) ;;
    *) fail "unsupported distribution \"${os_id:-unknown}\"; the Zabbly repository serves Debian and Ubuntu only" ;;
  esac
  command -v apt-get >/dev/null 2>&1 \
    || fail "distribution \"${os_id}\" is supported, but the image has no apt-get; use an image that has it"
  # shellcheck source=/dev/null
  codename="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME:-}")"
  [[ "${codename}" =~ ^[a-z]+$ ]] \
    || fail "/etc/os-release names no release codename (VERSION_CODENAME is \"${codename}\"), which names the" \
      "repository's suite; use a released Debian or Ubuntu image"
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) fail "unsupported architecture \"${machine}\"; the Zabbly repository serves amd64 and arm64 only" ;;
  esac
}

# Fails, before anything changes, when the remote user the Dev Container tooling names does not exist in the image.
check_remote_user() {
  id "${REMOTE_USER_NAME}" >/dev/null 2>&1 \
    || fail "the remote user \"${REMOTE_USER_NAME}\" does not exist in the image; create the user before this feature"
}

# Installs what the image lacks of curl, CA certificates, and GnuPG from the repositories the image configures.
install_prerequisites() {
  local packages=()
  if ! command -v curl >/dev/null 2>&1; then packages+=(curl); fi
  if [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then packages+=(ca-certificates); fi
  if ! command -v gpg >/dev/null 2>&1; then packages+=(gpg); fi
  if ((${#packages[@]} == 0)); then return 0; fi
  log "installing ${packages[*]} from the image's apt repositories"
  apt-get update \
    || fail "apt-get update failed; check the image's apt sources and the network"
  apt-get install --yes --no-install-recommends "${packages[@]}" \
    || fail "apt-get could not install ${packages[*]}; check the messages above"
}

# Fetches the Zabbly signing key and installs it as KEY_FILE only when the fetched file holds exactly one armored
# public key block with exactly one primary key, whose fingerprint is SIGNING_FINGERPRINT. The key is listed, never
# imported, in a GnuPG home inside the download directory.
install_key() {
  local blocks key_blocks listing primary_keys fingerprint
  log "downloading the repository's signing key from ${KEY_URL}"
  fetch --output "${work_dir}/key.asc" "${KEY_URL}" \
    || fail "cannot download ${KEY_URL}; check network access to pkgs.zabbly.com"
  # Exactly one armored block, a public key block: tools disagree on which further blocks of a file they read, and
  # only what gpg lists below is checked.
  blocks="$(grep --count '^-----BEGIN ' "${work_dir}/key.asc" || true)"
  key_blocks="$(grep --count --line-regexp --fixed-strings -- "${KEY_BLOCK_BEGIN}" "${work_dir}/key.asc" || true)"
  if [[ "${blocks}" != 1 || "${key_blocks}" != 1 ]]; then
    fail "the key was not accepted: ${KEY_URL} holds ${blocks} armored block(s), ${key_blocks} of them a public key" \
      "block, and the feature accepts exactly one public key block"
  fi
  mkdir --mode 0700 "${work_dir}/gnupg"
  listing="$(gpg --batch --homedir "${work_dir}/gnupg" --show-keys --with-colons "${work_dir}/key.asc")" \
    || fail "the key was not accepted: ${KEY_URL} does not hold an OpenPGP key that gpg can read"
  # In gpg's colon listing a primary key is a "pub" record, followed by an "fpr" record with its fingerprint in
  # field 10; subkeys are "sub" records with "fpr" records of their own.
  primary_keys="$(awk -F: '$1 == "pub" { count++ } END { print count + 0 }' <<<"${listing}")"
  fingerprint="$(awk -F: '$1 == "pub" { primary = 1 } $1 == "fpr" && primary { print $10; exit }' <<<"${listing}")"
  if [[ "${primary_keys}" != 1 || "${fingerprint}" != "${SIGNING_FINGERPRINT}" ]]; then
    fail "the key was not accepted: ${KEY_URL} holds ${primary_keys} primary key(s), the first with the fingerprint" \
      "\"${fingerprint}\", and the feature accepts exactly one, ${SIGNING_FINGERPRINT}; if Zabbly replaced its key," \
      "the feature needs a new version"
  fi
  log "the key has the pinned fingerprint ${SIGNING_FINGERPRINT}; installing it as ${KEY_FILE}"
  mkdir --parents "${KEYRINGS_DIR}"
  install --mode 0644 "${work_dir}/key.asc" "${KEY_FILE}"
}

# Defines the repository of the chosen channel in SOURCES_FILE, replacing the file as a whole, and reads its index.
define_repository() {
  log "defining the repository ${REPOSITORY_URL}/${CHANNEL} (suite ${codename}, ${arch}) in ${SOURCES_FILE}"
  cat >"${SOURCES_FILE}" <<EOF
Enabled: yes
Types: deb
URIs: ${REPOSITORY_URL}/${CHANNEL}
Suites: ${codename}
Components: main
Architectures: ${arch}
Signed-By: ${KEY_FILE}
EOF
  chmod 0644 "${SOURCES_FILE}"
  apt-get update \
    || fail "apt-get update failed with the Zabbly repository defined; the repository serves the suite" \
      "\"${codename}\" only for the Debian and Ubuntu releases its README lists (https://github.com/zabbly/incus)"
}

# Prints the newest version of the package $1 that the Zabbly repository of the chosen channel offers, and nothing
# when it offers none. `apt-cache madison` prints one line per version and source, newest first: package, version,
# and source, separated by " | ".
channel_version() {
  local line
  local fields=()
  while IFS= read -r line; do
    IFS='|' read -ra fields <<<"${line}"
    if [[ "${fields[2]:-}" == *" ${REPOSITORY_URL}/${CHANNEL} "* ]]; then
      printf '%s\n' "${fields[1]//[[:space:]]/}"
      return 0
    fi
  done < <(apt-cache madison "$1")
}

# Installs the Zabbly packages at the channel's newest version, named exactly: the distribution may ship packages of
# the same names, and a channel installed earlier may have left a newer version, which is then replaced by the older
# one (the feature's spec, Second install).
install_incus() {
  local version package
  local names=(incus-client incus-base)
  local packages=()
  if [[ "${VM}" == true ]]; then names+=(incus); fi
  version="$(channel_version incus-base)"
  [[ -n "${version}" ]] \
    || fail "the repository ${REPOSITORY_URL}/${CHANNEL} offers no incus-base for ${codename} on ${arch}; use an" \
      "image of a release the repository serves"
  for package in "${names[@]}"; do
    packages+=("${package}=${version}")
  done
  # The Zabbly packages need systemd-sysusers to create their groups; this small package provides it without
  # systemd. It is added only where no systemd-sysusers exists and the distribution release ships the package.
  if ! command -v systemd-sysusers >/dev/null 2>&1 \
    && apt-cache show systemd-standalone-sysusers >/dev/null 2>&1; then
    packages+=(systemd-standalone-sysusers)
  fi
  # incus-base depends on "nftables | iptables", and an image that holds iptables satisfies that without nft, which
  # the daemon then calls for its bridge wherever the kernel has nftables. The feature names nftables itself.
  packages+=(nftables)
  log "installing ${packages[*]} from ${REPOSITORY_URL}/${CHANNEL} and their dependencies"
  apt-get install --yes --no-install-recommends --allow-downgrades "${packages[@]}" \
    || fail "apt-get could not install ${packages[*]}; check the messages above"
}

# Adds the remote user to the incus-admin group, which the daemon's socket belongs to.
grant_remote_user() {
  if ! getent group "${ADMIN_GROUP}" >/dev/null; then
    log "creating the group ${ADMIN_GROUP}, which the packages did not create"
    groupadd --system "${ADMIN_GROUP}"
  fi
  if [[ "${REMOTE_USER_NAME}" == root ]]; then
    log "the remote user is root, which needs no group"
    return
  fi
  log "adding the remote user \"${REMOTE_USER_NAME}\" to the group ${ADMIN_GROUP}"
  usermod --append --groups "${ADMIN_GROUP}" "${REMOTE_USER_NAME}"
}

# Writes the settings start.sh reads at every start, and installs the two start scripts.
install_start_scripts() {
  mkdir --parents "${SHARE_DIR}" "${LOG_DIR}"
  log "recording initialize=${INITIALIZE} and the remote user in ${SETTINGS_FILE}"
  printf 'initialize=%s\nremoteUser=%s\n' "${INITIALIZE}" "${REMOTE_USER_NAME}" >"${SETTINGS_FILE}"
  chmod 0644 "${SETTINGS_FILE}"
  log "installing the entrypoint to ${START_SCRIPT} and the start check to ${CHECK_SCRIPT}"
  install --mode 0755 "${script_dir}/scripts/start.sh" "${START_SCRIPT}"
  install --mode 0755 "${script_dir}/scripts/check.sh" "${CHECK_SCRIPT}"
}

clean_caches() {
  apt-get clean
  rm --recursive --force "${APT_LISTS_DIR:?}"/*
}

main() {
  validate_options
  detect_platform
  check_remote_user
  trap cleanup EXIT
  # Every file and directory the install creates is readable by every user, whatever umask the build runs with.
  umask 022
  install_prerequisites
  work_dir="$(mktemp --directory)"
  install_key
  define_repository
  install_incus
  grant_remote_user
  install_start_scripts
  clean_caches
  log "done"
}

main "$@"
