#!/bin/sh
# Installs OpenTofu's tofu from its GitHub release archive to /usr/local/bin/tofu, after verifying the release's
# checksum list against its detached OpenPGP signature by upstream's release key, pinned by fingerprint, and the archive
# against that list. Writes no OpenTofu configuration and nothing under any home directory. Runs as root at image build
# time; the option `version` arrives as VERSION.
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly MIN_VERSION="1.6.3"
readonly RELEASES="https://github.com/opentofu/opentofu/releases"
readonly LATEST_URL="${RELEASES}/latest"
readonly KEY_URL="https://get.opentofu.org/opentofu.asc"
# The release key upstream's standalone installer pins (openspec/specs/opentofu/spec.md, "OpenTofu release
# signature"). Only a signature whose signer's primary key has this fingerprint is accepted.
readonly SIGNING_FINGERPRINT="E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80"
readonly TARGET="/usr/local/bin/tofu"
# The binary is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="${TARGET%/*}/.opentofu-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly PACMAN_CACHE_DIR="/var/cache/pacman/pkg"
readonly PACMAN_SYNC_DIR="/var/lib/pacman/sync"
readonly FAMILIES="the Debian, Ubuntu, Fedora, RHEL, Alpine, openSUSE, SUSE, or Arch Linux family"
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
  printf 'opentofu: %s\n' "$*"
}

fail() {
  printf 'opentofu: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged binary and the work directory on every exit, success or failure. Short options: BusyBox rm has
# no long ones.
cleanup() {
  if [ -n "${staged}" ]; then rm -f "${staged}"; fi
  if [ -n "${work}" ]; then rm -rf "${work}"; fi
}

# Prints $1 without a leading "v" when it is v?MAJOR.MINOR.PATCH of decimal numbers; else returns 1.
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
      '' | *[!0-9]*) return 1 ;;
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

# Runs curl over HTTPS only, on every hop including redirects, with failing HTTP statuses as errors. --retry 3 handles
# a known failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Downloads URL $1 to file $2, following redirects: GitHub serves release assets from its asset host. Logs the final
# URL without its query string, which holds a short-lived token, so a host change shows in the build log. Fails with
# the remaining arguments as the message when the download fails.
download() {
  download_url="$1"
  download_file="$2"
  shift 2
  download_final="$(fetch --location --output "${download_file}" --write-out '%{url_effective}' "${download_url}")" \
    || fail "$@"
  log "downloaded ${download_url} to ${download_file} (final URL: ${download_final%%\?*})"
}

# Runs the tofu at $1 with the remaining arguments in a cleared environment that holds only PATH and a HOME inside the
# work directory: every tofu run creates ~/.terraform.d, and no TF_* variable of the build can change what it prints.
run_tofu() {
  run_tofu_binary="$1"
  shift
  env --ignore-environment PATH="${PATH}" HOME="${work}/home" "${run_tofu_binary}" "$@"
}

# Succeeds when the first line of `tofu version` output $1 is "OpenTofu v${version}".
is_requested_version() {
  [ "${1%%"${NEWLINE}"*}" = "OpenTofu v${version}" ]
}

# Fails unless VERSION is "latest" or a release version at or above MIN_VERSION. Sets ${version} to the release version
# without its leading "v", and leaves it empty for "latest".
validate_options() {
  if [ "${VERSION}" = "latest" ]; then return 0; fi
  if ! version="$(normalize_version "${VERSION}")"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release version MAJOR.MINOR.PATCH such as 1.13.9, with or without a leading \"v\""
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

# Succeeds when every prerequisite is present: curl, a CA certificate bundle, gpg, tar, and gzip.
has_prerequisites() {
  for has_prerequisites_command in curl gpg tar gzip; do
    command -v "${has_prerequisites_command}" >/dev/null 2>&1 || return 1
  done
  has_ca_bundle
}

# Installs what the image lacks of curl, CA certificates, GnuPG, tar, and gzip, which the install needs, in one
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
  # BusyBox's tar and gzip, present on Alpine, are enough.
  if ! command -v tar >/dev/null 2>&1; then set -- "$@" tar; fi
  if ! command -v gzip >/dev/null 2>&1; then set -- "$@" gzip; fi
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
    || fail "curl, CA certificates, gpg, tar, or gzip is still missing after installing $*;" \
      "install them in the image"
}

# Sets ${version} to the release the latest-release link redirects to, read without following the redirect. Upstream
# signs nothing about the link, so it relies on TLS alone; the release it names is still verified like an explicit
# version (openspec/specs/opentofu/spec.md, "OpenTofu release metadata trust").
resolve_latest() {
  resolve_latest_location="$(fetch --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")" \
    || fail "cannot read ${LATEST_URL}; check network access to github.com, or set version to a release"
  [ -n "${resolve_latest_location}" ] \
    || fail "${LATEST_URL} did not redirect to a release; set version to a release"
  log "read the latest release from ${LATEST_URL}: ${resolve_latest_location}"
  # The Location header may be absolute or relative, and curl prints the URL it resolves to. The tag is the last path
  # segment of that URL, without a query, a fragment, or a trailing slash.
  resolve_latest_tag="${resolve_latest_location%%[?#]*}"
  resolve_latest_tag="${resolve_latest_tag%/}"
  resolve_latest_tag="${resolve_latest_tag##*/}"
  if ! version="$(normalize_version "${resolve_latest_tag}")" \
    || ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "the latest release is \"${resolve_latest_tag}\", not a release version MAJOR.MINOR.PATCH at or above" \
      "${MIN_VERSION}; set version to a release"
  fi
}

# Ends the install with status 0 when ${TARGET} already reports ${version}. A tofu that exits non-zero or prints
# anything else is replaced. Its stderr is discarded, here and in stage_binary: a notice there is not the version.
skip_when_installed() {
  [ -f "${TARGET}" ] || return 0
  if ! skip_when_installed_output="$(run_tofu "${TARGET}" version 2>/dev/null)"; then
    return 0
  fi
  if is_requested_version "${skip_when_installed_output}"; then
    log "OpenTofu ${version} is already installed at ${TARGET}; leaving it unchanged"
    exit 0
  fi
}

# Downloads the release's checksum list, its detached signature, and upstream's key into ${work}, and fails unless the
# signature is good and made by the key whose primary fingerprint is ${SIGNING_FINGERPRINT}. The keyring lives in
# ${work}, and no option weakens GnuPG's checks.
verify_checksum_list() {
  verify_checksum_list_sums="tofu_${version}_SHA256SUMS"
  verify_checksum_list_url="${RELEASES}/download/v${version}/${verify_checksum_list_sums}"
  download "${verify_checksum_list_url}" "${work}/SHA256SUMS" \
    "cannot download ${verify_checksum_list_url};" \
    "check that release v${version} exists and that github.com is reachable"
  download "${verify_checksum_list_url}.gpgsig" "${work}/SHA256SUMS.gpgsig" \
    "verification failed: cannot download ${verify_checksum_list_url}.gpgsig, the signature of the checksum list;" \
    "retry the build, and set version to another release if it persists"
  fetch --output "${work}/opentofu.asc" "${KEY_URL}" \
    || fail "cannot download ${KEY_URL}; check network access to get.opentofu.org"
  log "downloaded ${KEY_URL} to ${work}/opentofu.asc"

  # The key is turned into a keyring file and used in place, not imported: importing starts gpg-agent, which the
  # minimal gpg packages of Debian and Alpine do not include, and verifying needs no agent.
  mkdir -m 700 "${work}/gnupg"
  gpg --batch --homedir "${work}/gnupg" --output "${work}/opentofu.gpg" --dearmor "${work}/opentofu.asc" \
    2>"${work}/gpg-key.log" \
    || fail "cannot read the key from ${KEY_URL}: $(cat "${work}/gpg-key.log")"
  if ! gpg --batch --homedir "${work}/gnupg" --no-default-keyring --keyring "${work}/opentofu.gpg" \
    --status-file "${work}/gpg-status" --verify "${work}/SHA256SUMS.gpgsig" "${work}/SHA256SUMS" \
    2>"${work}/gpg-verify.log"; then
    fail "verification failed: the signature of ${verify_checksum_list_url} does not verify:" \
      "$(cat "${work}/gpg-verify.log")"
  fi
  # Every signature must be good and made by the pinned primary key; the last field of VALIDSIG is the primary key's
  # fingerprint.
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
  archive="tofu_${version}_linux_${arch}.tar.gz"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/SHA256SUMS" >"${work}/archive.sha256"
  download_archive_entries="$(awk 'END { print NR }' "${work}/archive.sha256")"
  # No entry means the release publishes no archive for this architecture; several mean a list that cannot be trusted
  # to name the archive.
  [ "${download_archive_entries}" != "0" ] \
    || fail "verification failed: the checksum list of release v${version} holds no entry for ${archive};" \
      "set version to a release that has an archive for linux ${arch}"
  [ "${download_archive_entries}" = "1" ] \
    || fail "verification failed: the checksum list of release v${version} holds" \
      "${download_archive_entries} entries for ${archive}, expected exactly one"

  download_archive_url="${RELEASES}/download/v${version}/${archive}"
  download "${download_archive_url}" "${work}/${archive}" \
    "cannot download ${download_archive_url}; check that release v${version} has an archive for linux ${arch}"
  # Short option: BusyBox sha256sum has no long ones.
  (cd "${work}" && sha256sum -c archive.sha256) \
    || fail "verification failed: ${archive} does not match its entry in the checksum list;" \
      "retry the build, and set version to another release if it persists"
}

# Extracts tofu from the archive and stages it next to ${TARGET}, checking that it reports ${version}.
stage_binary() {
  mkdir "${work}/extract"
  tar --extract --gzip --file "${work}/${archive}" --directory "${work}/extract" tofu \
    || fail "cannot extract tofu from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [ ! -f "${work}/extract/tofu" ] || [ -L "${work}/extract/tofu" ]; then
    fail "${archive} does not hold tofu as a regular file; set version to another release"
  fi
  mkdir -p "${TARGET%/*}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work}/extract/tofu" "${staged}"
  chmod 0755 "${staged}"
  if ! stage_binary_output="$(run_tofu "${staged}" version 2>/dev/null)" \
    || ! is_requested_version "${stage_binary_output}"; then
    fail "the tofu from ${archive} does not run or does not report v${version}:" \
      "\"${stage_binary_output%%"${NEWLINE}"*}\""
  fi
}

# Renames the staged binary over ${TARGET}, so the target is replaced in one step.
install_binary() {
  mv -f "${staged}" "${TARGET}"
  staged=""
  log "installed OpenTofu ${version} from ${archive} to ${TARGET}"
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
  work="$(mktemp -d "${TMPDIR:-/tmp}/opentofu-feature.XXXXXX")"
  mkdir -m 700 "${work}/home"
  if [ "${VERSION}" = "latest" ]; then resolve_latest; fi
  skip_when_installed
  verify_checksum_list
  download_archive
  stage_binary
  install_binary
}

main "$@"
