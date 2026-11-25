#!/bin/sh
# Installs HashiCorp Packer's packer from its release archive at releases.hashicorp.com to /usr/local/bin/packer, after
# verifying the release's checksum list against its detached OpenPGP signature by upstream's release key, pinned by
# fingerprint, and the archive against that list. Installs no Packer plugin, writes no Packer configuration, and writes
# nothing under any home directory. Runs as root at image build time; the option `version` arrives as VERSION.
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly MIN_VERSION="1.7.0"
readonly RELEASES="https://releases.hashicorp.com/packer"
# HashiCorp's Checkpoint service, which Packer itself asks for its current version; read only for version "latest".
readonly CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check/packer"
readonly KEY_URL="https://www.hashicorp.com/.well-known/pgp-key.txt"
# The release key upstream's verification guide names (openspec/specs/packer/spec.md, "Packer release signature").
# Only a signature whose signer's primary key has this fingerprint is accepted.
readonly SIGNING_FINGERPRINT="C874011F0AB405110D02105534365D9472D7468F"
readonly TARGET="/usr/local/bin/packer"
# The binary is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="${TARGET%/*}/.packer-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly PACMAN_CACHE_DIR="/var/cache/pacman/pkg"
readonly PACMAN_SYNC_DIR="/var/lib/pacman/sync"
readonly FAMILIES="the Debian, Ubuntu, Fedora, RHEL, Alpine, openSUSE, SUSE, or Arch Linux family"
# The text that precedes the current version in the Checkpoint answer, a one-line JSON object.
readonly CURRENT_VERSION_KEY='"current_version":"'
# A newline, for cutting command output to its first line with parameter expansion.
readonly NEWLINE='
'

VERSION="${VERSION-latest}"

version=""
arch=""
pm=""
archive=""
work=""
staged=""

log() {
  printf 'packer: %s\n' "$*"
}

fail() {
  printf 'packer: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged binary and the work directory on every exit, success or failure. Short options: BusyBox rm has
# no long ones.
cleanup() {
  if [ -n "${staged}" ]; then rm -f "${staged}"; fi
  if [ -n "${work}" ]; then rm -rf "${work}"; fi
}

# Prints $1 without a leading "v" when it is v?MAJOR.MINOR.PATCH of decimal numbers without leading zeros, as
# release versions are; else returns 1.
normalize_version() {
  normalize_version_value="${1#v}"
  case "${normalize_version_value}" in
    *.*.*.*) return 1 ;;
    *.*.*) ;;
    *) return 1 ;;
  esac
  normalize_version_major="${normalize_version_value%%.*}"
  normalize_version_rest="${normalize_version_value#*.}"
  normalize_version_minor="${normalize_version_rest%%.*}"
  normalize_version_patch="${normalize_version_rest#*.}"
  for normalize_version_part in \
    "${normalize_version_major}" "${normalize_version_minor}" "${normalize_version_patch}"; do
    case "${normalize_version_part}" in
      '' | *[!0-9]* | 0?*) return 1 ;;
    esac
  done
  printf '%s\n' "${normalize_version_value}"
}

# Succeeds when normalized version $1 is at or above normalized version $2.
version_at_least() {
  version_at_least_a="$1"
  version_at_least_b="$2"
  for _ in 1 2 3; do
    version_at_least_x="${version_at_least_a%%.*}"
    version_at_least_y="${version_at_least_b%%.*}"
    if [ "${version_at_least_x}" -gt "${version_at_least_y}" ]; then return 0; fi
    if [ "${version_at_least_x}" -lt "${version_at_least_y}" ]; then return 1; fi
    version_at_least_a="${version_at_least_a#*.}"
    version_at_least_b="${version_at_least_b#*.}"
  done
  return 0
}

# Downloads URL $1 to file $2 over HTTPS without following a redirect: every URL this feature requests answers
# directly, so anything but status 200 fails, a redirect included. Fails with the remaining arguments as the message
# when the request itself fails. --retry 3 handles a known failure mode: a transient network error.
download() {
  download_url="$1"
  download_file="$2"
  shift 2
  download_status="$(curl --proto '=https' --fail --silent --show-error --retry 3 \
    --output "${download_file}" --write-out '%{http_code}' "${download_url}")" \
    || fail "$@"
  [ "${download_status}" = "200" ] \
    || fail "${download_url} answered with HTTP status ${download_status}, not 200, and a redirect is not followed;" \
      "retry the build"
  log "downloaded ${download_url} to ${download_file}"
}

# Runs the packer at $1 with the remaining arguments in a cleared environment that holds only PATH, a HOME inside the
# work directory, and CHECKPOINT_DISABLE: every packer run writes a file under HOME, an outdated packer otherwise asks
# the Checkpoint service, and no PACKER_* variable of the build can change what it prints. It runs in that empty HOME,
# in a subshell: releases up to 1.10 execute any packer-plugin-* file of the current directory on every run.
run_packer() {
  run_packer_binary="$1"
  shift
  (
    cd "${work}/home"
    env --ignore-environment PATH="${PATH}" HOME="${work}/home" CHECKPOINT_DISABLE=1 "${run_packer_binary}" "$@"
  )
}

# Succeeds when the first line of `packer version` output $1 is "Packer v${version}".
is_requested_version() {
  [ "${1%%"${NEWLINE}"*}" = "Packer v${version}" ]
}

# Fails unless VERSION is "latest" or a release version at or above MIN_VERSION. Sets ${version} to the release version
# without its leading "v", and leaves it empty for "latest".
validate_options() {
  if [ "${VERSION}" = "latest" ]; then return 0; fi
  if ! version="$(normalize_version "${VERSION}")"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release version MAJOR.MINOR.PATCH such as 1.15.4, with or without a leading \"v\""
  fi
  if ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
  fi
}

# Fails unless the machine is x86_64 or aarch64 and the image belongs to a supported family and has that family's
# package manager; sets ${arch} to upstream's archive name for the machine and ${pm}. Runs before VERSION becomes
# readonly: /etc/os-release assigns it too.
detect_platform() {
  detect_platform_machine="$(uname --machine)"
  case "${detect_platform_machine}" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) fail "unsupported architecture \"${detect_platform_machine}\"; use an x86_64 or aarch64 machine" ;;
  esac

  [ -f /etc/os-release ] \
    || fail "/etc/os-release is missing, so the distribution cannot be identified; use an image of ${FAMILIES}"
  # Read in subshells: os-release sets VERSION, which would overwrite the option.
  # shellcheck source=/dev/null
  detect_platform_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  detect_platform_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"

  # openSUSE's IDs (opensuse-leap, opensuse-tumbleweed) name the family by prefix. Otherwise ID decides first, then
  # each word of ID_LIKE in order. The two values are unquoted to split them into words, and set -f keeps a word from
  # expanding as a glob.
  case "${detect_platform_id}" in
    opensuse*) pm=zypper ;;
  esac
  set -f
  for detect_platform_family in ${detect_platform_id} ${detect_platform_id_like}; do
    if [ -n "${pm}" ]; then break; fi
    case "${detect_platform_family}" in
      debian | ubuntu) pm=apt-get ;;
      rhel | centos | fedora) pm=dnf ;;
      alpine) pm=apk ;;
      suse | opensuse) pm=zypper ;;
      arch) pm=pacman ;;
    esac
  done
  set +f
  [ -n "${pm}" ] \
    || fail "unsupported distribution \"${detect_platform_id}\" (ID_LIKE \"${detect_platform_id_like}\");" \
      "use an image of ${FAMILIES}"
  command -v "${pm}" >/dev/null 2>&1 \
    || fail "distribution \"${detect_platform_id}\" is in a supported family," \
      "but its package manager ${pm} is missing; use an image that has ${pm}"
}

# Fails when ${TARGET} exists but is not a regular file, or when its directory exists but is not a directory: a rename
# over a directory would put the binary inside it, and a symbolic link would be replaced, not followed, so either would
# leave the install reporting success with the binary somewhere else.
check_target() {
  if [ -e "${TARGET}" ] || [ -L "${TARGET}" ]; then
    if [ ! -f "${TARGET}" ] || [ -L "${TARGET}" ]; then
      fail "${TARGET} exists but is not a regular file; remove it, then install again"
    fi
  fi
  if [ -e "${TARGET%/*}" ] && [ ! -d "${TARGET%/*}" ]; then
    fail "${TARGET%/*} exists but is not a directory; remove it, then install again"
  fi
}

# Succeeds when the image has a CA certificate bundle where one of the supported distributions keeps it.
has_ca_bundle() {
  for has_ca_bundle_file in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    if [ -s "${has_ca_bundle_file}" ]; then return 0; fi
  done
  return 1
}

# Succeeds when every prerequisite is present: curl, a CA certificate bundle, gpg, and unzip.
has_prerequisites() {
  for has_prerequisites_command in curl gpg unzip; do
    command -v "${has_prerequisites_command}" >/dev/null 2>&1 || return 1
  done
  has_ca_bundle
}

# Installs what the image lacks of curl, CA certificates, GnuPG, and unzip, which the install needs, in one
# transaction, and cleans the package manager's cache. The missing packages are this function's positional parameters.
install_packages() {
  set --
  if ! command -v curl >/dev/null 2>&1; then set -- "$@" curl; fi
  if ! has_ca_bundle; then
    case "${pm}" in
      zypper) set -- "$@" ca-certificates-mozilla ;;
      *) set -- "$@" ca-certificates ;;
    esac
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    case "${pm}" in
      apt-get | apk) set -- "$@" gpg ;;
      dnf) set -- "$@" gnupg2 ;;
      zypper) set -- "$@" gpg2 ;;
      pacman) set -- "$@" gnupg ;;
    esac
  fi
  # BusyBox's unzip, present on Alpine, is enough.
  if ! command -v unzip >/dev/null 2>&1; then set -- "$@" unzip; fi
  if [ "$#" -eq 0 ]; then return 0; fi

  log "installing missing packages with ${pm}: $*"
  case "${pm}" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update \
        || fail "apt-get update failed; check the image's package repositories and network access"
      DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@" \
        || fail "apt-get install failed; check the image's package repositories and network access"
      apt-get clean
      rm -rf "${APT_LISTS_DIR:?}"/*
      ;;
    dnf)
      dnf install --assumeyes --setopt=install_weak_deps=False "$@" \
        || fail "dnf install failed; check the image's package repositories and network access"
      dnf clean all
      ;;
    apk)
      apk add --no-cache "$@" \
        || fail "apk add failed; check the image's package repositories and network access"
      ;;
    zypper)
      zypper --non-interactive install --no-recommends "$@" \
        || fail "zypper install failed; check the image's package repositories and network access"
      zypper --non-interactive clean --all
      ;;
    pacman)
      # Arch supports installing a package only together with a full system upgrade.
      pacman --sync --refresh --sysupgrade --needed --noconfirm "$@" \
        || fail "pacman failed to install the packages; check the image's package repositories and network access"
      rm -rf "${PACMAN_CACHE_DIR:?}"/* "${PACMAN_SYNC_DIR:?}"/*
      ;;
  esac
  has_prerequisites \
    || fail "curl, CA certificates, gpg, or unzip is still missing after installing $*; install them in the image"
}

# Sets ${version} to the current version the Checkpoint service reports. Upstream signs nothing about the answer, so it
# relies on TLS alone; the release it names is still verified like an explicit version (openspec/specs/packer/spec.md,
# "Packer release metadata trust"). The answer must name exactly one current version, and that value passes the same
# validation as the option, so no JSON parser is needed: the validation decides what is accepted.
resolve_latest() {
  download "${CHECKPOINT_URL}" "${work}/checkpoint.json" \
    "cannot read ${CHECKPOINT_URL}; check network access to checkpoint-api.hashicorp.com, or set version to a release"
  resolve_latest_answer="$(cat "${work}/checkpoint.json")"
  resolve_latest_rest="${resolve_latest_answer#*"${CURRENT_VERSION_KEY}"}"
  [ "${resolve_latest_rest}" != "${resolve_latest_answer}" ] \
    || fail "the answer of ${CHECKPOINT_URL} names no current_version; set version to a release"
  case "${resolve_latest_rest}" in
    *"${CURRENT_VERSION_KEY}"*)
      fail "the answer of ${CHECKPOINT_URL} names more than one current_version; set version to a release"
      ;;
  esac
  resolve_latest_value="${resolve_latest_rest%%\"*}"
  log "read the current version from ${CHECKPOINT_URL}: ${resolve_latest_value}"
  if ! version="$(normalize_version "${resolve_latest_value}")" \
    || ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "the current version is \"${resolve_latest_value}\", not a release version MAJOR.MINOR.PATCH at or above" \
      "${MIN_VERSION}; set version to a release"
  fi
}

# Ends the install with status 0 when ${TARGET} already reports ${version}. A packer that exits non-zero or prints
# anything else is replaced. Its stderr is discarded, here and in stage_binary: a notice there is not the version.
skip_when_installed() {
  [ -f "${TARGET}" ] || return 0
  if ! skip_when_installed_output="$(run_packer "${TARGET}" version 2>/dev/null)"; then
    return 0
  fi
  if is_requested_version "${skip_when_installed_output}"; then
    log "Packer ${version} is already installed at ${TARGET}; leaving it unchanged"
    exit 0
  fi
}

# Downloads the release's checksum list, its detached signature, and upstream's key into ${work}, and fails unless the
# signature is good and made by the key whose primary fingerprint is ${SIGNING_FINGERPRINT}. The keyring lives in
# ${work}, and no option weakens GnuPG's checks.
verify_checksum_list() {
  verify_checksum_list_sums="packer_${version}_SHA256SUMS"
  verify_checksum_list_url="${RELEASES}/${version}/${verify_checksum_list_sums}"
  download "${verify_checksum_list_url}" "${work}/SHA256SUMS" \
    "cannot download ${verify_checksum_list_url};" \
    "check that release ${version} exists and that releases.hashicorp.com is reachable"
  download "${verify_checksum_list_url}.sig" "${work}/SHA256SUMS.sig" \
    "verification failed: cannot download ${verify_checksum_list_url}.sig, the signature of the checksum list;" \
    "retry the build, and set version to another release if it persists"
  download "${KEY_URL}" "${work}/hashicorp.asc" \
    "cannot download ${KEY_URL}; check network access to www.hashicorp.com"

  # The key is turned into a keyring file and used in place, not imported: importing starts gpg-agent, which the
  # minimal gpg packages of Debian and Alpine do not include, and verifying needs no agent.
  mkdir -m 700 "${work}/gnupg"
  gpg --batch --homedir "${work}/gnupg" --output "${work}/hashicorp.gpg" --dearmor "${work}/hashicorp.asc" \
    2>"${work}/gpg-key.log" \
    || fail "cannot read the key from ${KEY_URL}: $(cat "${work}/gpg-key.log")"
  if ! gpg --batch --homedir "${work}/gnupg" --no-default-keyring --keyring "${work}/hashicorp.gpg" \
    --status-file "${work}/gpg-status" --verify "${work}/SHA256SUMS.sig" "${work}/SHA256SUMS" \
    2>"${work}/gpg-verify.log"; then
    fail "verification failed: the signature of ${verify_checksum_list_url} does not verify:" \
      "$(cat "${work}/gpg-verify.log")"
  fi
  # Every signature must be good and made under the pinned primary key. Upstream signs with a subkey, so the
  # fingerprint compared is the last field of VALIDSIG, the primary key's. KEYEXPIRED is not in the list: upstream's
  # key file carries an expired earlier subkey, which GnuPG reports on every run; a signature made by an expired key is
  # EXPKEYSIG.
  if grep -q -E '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG) ' "${work}/gpg-status"; then
    fail "verification failed: ${verify_checksum_list_url} carries a signature that is not good"
  fi
  verify_checksum_list_signers="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "${work}/gpg-status")"
  [ -n "${verify_checksum_list_signers}" ] \
    || fail "verification failed: ${verify_checksum_list_url} carries no valid signature"
  for verify_checksum_list_signer in ${verify_checksum_list_signers}; do
    [ "${verify_checksum_list_signer}" = "${SIGNING_FINGERPRINT}" ] \
      || fail "verification failed: ${verify_checksum_list_url} is signed by ${verify_checksum_list_signer}," \
        "not by the release key ${SIGNING_FINGERPRINT}"
  done
  log "verified the signature of ${verify_checksum_list_sums} by ${SIGNING_FINGERPRINT}"
}

# Downloads the archive and fails unless the verified checksum list holds exactly one entry for it and its SHA-256
# digest equals that entry.
download_archive() {
  archive="packer_${version}_linux_${arch}.zip"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/SHA256SUMS" >"${work}/archive.sha256"
  download_archive_entries="$(awk 'END { print NR }' "${work}/archive.sha256")"
  # No entry means the release publishes no archive for this architecture; several mean a list that cannot be trusted
  # to name the archive.
  [ "${download_archive_entries}" != "0" ] \
    || fail "verification failed: the checksum list of release ${version} holds no entry for ${archive};" \
      "set version to a release that has an archive for linux ${arch}"
  [ "${download_archive_entries}" = "1" ] \
    || fail "verification failed: the checksum list of release ${version} holds" \
      "${download_archive_entries} entries for ${archive}, expected exactly one"

  download_archive_url="${RELEASES}/${version}/${archive}"
  download "${download_archive_url}" "${work}/${archive}" \
    "cannot download ${download_archive_url}; check that release ${version} has an archive for linux ${arch}"
  # Short option: BusyBox sha256sum has no long ones.
  (cd "${work}" && sha256sum -c archive.sha256) \
    || fail "verification failed: ${archive} does not match its entry in the checksum list;" \
      "retry the build, and set version to another release if it persists"
}

# Extracts only packer from the archive, which may also hold a license file, and stages it next to ${TARGET}, checking
# that it reports ${version}.
stage_binary() {
  mkdir "${work}/extract"
  # Short options: BusyBox unzip has no long ones.
  unzip -q "${work}/${archive}" packer -d "${work}/extract" \
    || fail "cannot extract packer from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [ ! -f "${work}/extract/packer" ] || [ -L "${work}/extract/packer" ]; then
    fail "${archive} does not hold packer as a regular file; set version to another release"
  fi
  mkdir -p "${TARGET%/*}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work}/extract/packer" "${staged}"
  chmod 0755 "${staged}"
  if ! stage_binary_output="$(run_packer "${staged}" version 2>/dev/null)" \
    || ! is_requested_version "${stage_binary_output}"; then
    fail "the packer from ${archive} does not run or does not report v${version}:" \
      "\"${stage_binary_output%%"${NEWLINE}"*}\""
  fi
}

# Renames the staged binary over ${TARGET}, so the target is replaced in one step.
install_binary() {
  mv -f "${staged}" "${TARGET}"
  staged=""
  log "installed Packer ${version} from ${archive} to ${TARGET}"
}

main() {
  validate_options
  detect_platform
  readonly VERSION

  trap cleanup EXIT
  # dash does not run the EXIT trap when a signal ends the script; exiting from the signal's trap runs it, with the
  # status a shell reports for that signal.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Every directory the install creates is 0755, whatever umask the build runs with; files get explicit modes.
  umask 022

  check_target
  install_packages
  work="$(mktemp -d "${TMPDIR:-/tmp}/packer-feature.XXXXXX")"
  mkdir -m 700 "${work}/home"
  if [ "${VERSION}" = "latest" ]; then resolve_latest; fi
  skip_when_installed
  verify_checksum_list
  download_archive
  stage_binary
  install_binary
}

main "$@"
