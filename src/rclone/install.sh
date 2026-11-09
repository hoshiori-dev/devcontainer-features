#!/bin/sh
# Installs rclone from its release archive on downloads.rclone.org to /usr/local/bin/rclone, after verifying the
# release's checksum list against upstream's release key, pinned by fingerprint, and the archive against the signed
# list. Writes the bash, zsh, and fish completion scripts the installed rclone generates. With
# installMountDependencies, also installs fuse3 for rclone mount; grants no privilege and writes no rclone
# configuration. Runs as root at image build time; options arrive as environment variables:
#   version: VERSION
#   installMountDependencies: INSTALLMOUNTDEPENDENCIES
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly MIN_VERSION="1.63.0"
readonly DOWNLOADS="https://downloads.rclone.org"
readonly VERSION_URL="${DOWNLOADS}/version.txt"
readonly KEYS_URL="https://rclone.org/KEYS"
# The release key https://rclone.org/release_signing/ documents (openspec/specs/rclone/spec.md, "rclone release
# signature"). The key list also holds other keys; only a signature by this primary key is accepted.
readonly SIGNING_FINGERPRINT="FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA"
readonly CHECKSUMS="SHA256SUMS"
readonly TARGET="/usr/local/bin/rclone"
readonly BASH_COMPLETION="/usr/local/share/bash-completion/completions/rclone"
readonly ZSH_COMPLETION="/usr/local/share/zsh/site-functions/_rclone"
# fish searches no directory under /usr/local/share, so its vendor directory under /usr/share is used.
readonly FISH_COMPLETION="/usr/share/fish/vendor_completions.d/rclone.fish"
# Every staged file sits next to its target, so the rename over the target stays on one file system.
readonly STAGING_NAME=".rclone-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly FAMILIES="the Debian, Ubuntu, Fedora, or Alpine family"

VERSION="${VERSION-latest}"
INSTALLMOUNTDEPENDENCIES="${INSTALLMOUNTDEPENDENCIES-false}"

version=""
arch=""
pm=""
gpg_package=""
archive=""
work=""
staged=""
staged_bash=""
staged_zsh=""
staged_fish=""
installed="false"

log() {
  printf 'rclone: %s\n' "$*"
}

fail() {
  printf 'rclone: error: %s\n' "$*" >&2
  exit 1
}

# Removes every staged file and the work directory on every exit, success or failure. Short options: BusyBox rm has no
# long ones.
cleanup() {
  for cleanup_file in "${staged}" "${staged_bash}" "${staged_zsh}" "${staged_fish}"; do
    if [ -n "${cleanup_file}" ]; then rm -f "${cleanup_file}"; fi
  done
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

# Runs curl over HTTPS only, with failing HTTP statuses as errors. --location with --max-redirs 0 makes a redirect an
# error without contacting its target: no URL the feature uses redirects, so a redirect would lead to a host the spec
# does not name. --retry 3 handles a known failure mode: a transient network error.
fetch() {
  curl --proto '=https' --location --max-redirs 0 --fail --silent --show-error --retry 3 "$@"
}

# Runs the rclone at $1 with the remaining arguments, isolated from the image: every home and configuration path points
# into the work directory, so the run reads no real configuration and writes nothing outside ${work}.
run_rclone() {
  run_rclone_binary="$1"
  shift
  env HOME="${work}/home" XDG_CONFIG_HOME="${work}/home/.config" XDG_CACHE_HOME="${work}/home/.cache" \
    RCLONE_CONFIG="${work}/home/.config/rclone/rclone.conf" "${run_rclone_binary}" "$@"
}

# Fails unless VERSION is "latest" or a release version at or above MIN_VERSION, and INSTALLMOUNTDEPENDENCIES is a
# boolean. Sets ${version} to the release version without its leading "v", and leaves it empty for "latest".
validate_options() {
  case "${INSTALLMOUNTDEPENDENCIES}" in
    true | false) ;;
    *) fail "option installMountDependencies is \"${INSTALLMOUNTDEPENDENCIES}\"; use true or false" ;;
  esac
  if [ "${VERSION}" = "latest" ]; then return 0; fi
  if ! version="$(normalize_version "${VERSION}")"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release version MAJOR.MINOR.PATCH such as 1.70.0, with or without a leading \"v\""
  fi
  if ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
  fi
}

# Fails unless the machine is x86_64 or aarch64 and the image belongs to a supported family and has that family's
# package manager; sets ${arch} to upstream's archive name for the machine, ${pm}, and ${gpg_package}. Runs before
# VERSION becomes readonly: /etc/os-release assigns it too.
detect_platform() {
  detect_platform_machine="$(uname -m)"
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

  # ID decides first, then each word of ID_LIKE in order. The two values are unquoted to split them into words, and
  # set -f keeps a word from expanding as a glob.
  set -f
  for detect_platform_family in ${detect_platform_id} ${detect_platform_id_like}; do
    case "${detect_platform_family}" in
      debian | ubuntu)
        pm=apt-get
        gpg_package=gpg
        break
        ;;
      fedora)
        pm=dnf
        gpg_package=gnupg2
        break
        ;;
      alpine)
        pm=apk
        gpg_package=gpg
        break
        ;;
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

# Fails when a file the install replaces exists but is not a regular file, or when its directory exists but is not a
# directory: a rename over a directory would put the file inside it, and a symbolic link would be replaced, not
# followed, so either would leave the install reporting success with the file somewhere else.
check_targets() {
  for check_targets_path in "${TARGET}" "${BASH_COMPLETION}" "${ZSH_COMPLETION}" "${FISH_COMPLETION}"; do
    if [ -e "${check_targets_path}" ] || [ -L "${check_targets_path}" ]; then
      if [ ! -f "${check_targets_path}" ] || [ -L "${check_targets_path}" ]; then
        fail "${check_targets_path} exists but is not a regular file; remove it, then install again"
      fi
    fi
    check_targets_dir="${check_targets_path%/*}"
    if [ -e "${check_targets_dir}" ] && [ ! -d "${check_targets_dir}" ]; then
      fail "${check_targets_dir} exists but is not a directory; remove it, then install again"
    fi
  done
}

# Succeeds when the package manager records package $1 as installed. Known failure mode: dpkg-query exits 1 for a
# package dpkg has no record of; any failed query counts as not installed.
package_installed() {
  case "${pm}" in
    apt-get)
      if ! package_installed_status="$(dpkg-query --show --showformat '${Status}' "$1" 2>/dev/null)"; then
        return 1
      fi
      case "${package_installed_status}" in
        *'install ok installed'*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    dnf) rpm --query "$1" >/dev/null 2>&1 ;;
    apk) apk info --installed "$1" >/dev/null 2>&1 ;;
  esac
}

# Installs what the image lacks of curl, GnuPG, unzip, and ca-certificates, which the install needs, and fuse3 when
# requested, in one transaction, and cleans the package manager's cache. The missing packages are this function's
# positional parameters.
install_packages() {
  set --
  if ! command -v curl >/dev/null 2>&1; then set -- "$@" curl; fi
  if ! command -v gpg >/dev/null 2>&1; then set -- "$@" "${gpg_package}"; fi
  # BusyBox's unzip, present on Alpine, is enough.
  if ! command -v unzip >/dev/null 2>&1; then set -- "$@" unzip; fi
  if ! package_installed ca-certificates; then set -- "$@" ca-certificates; fi
  if [ "${INSTALLMOUNTDEPENDENCIES}" = "true" ] && ! package_installed fuse3; then set -- "$@" fuse3; fi
  if [ "$#" -eq 0 ]; then return 0; fi

  log "installing missing packages with ${pm}: $*"
  case "${pm}" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update \
        || fail "apt-get update failed; check the image's package repositories and network access"
      DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@" \
        || fail "apt-get install failed; check the image's package repositories and network access"
      rm -rf "${APT_LISTS_DIR:?}"/*
      ;;
    dnf)
      dnf install --assumeyes "$@" \
        || fail "dnf install failed; check the image's package repositories and network access"
      dnf clean all
      ;;
    apk)
      apk add --no-cache "$@" \
        || fail "apk add failed; check the image's package repositories and network access"
      ;;
  esac
}

# Sets ${version} to the release the version file names in its single line "rclone v<version>". Upstream publishes the
# file unsigned, so it relies on TLS alone; whatever it names is still verified like an explicit version
# (openspec/specs/rclone/spec.md, "rclone release metadata trust").
resolve_latest() {
  fetch --output "${work}/version.txt" "${VERSION_URL}" \
    || fail "cannot download ${VERSION_URL}; check network access to downloads.rclone.org, or set version to a release"
  resolve_latest_lines="$(awk 'END { print NR }' "${work}/version.txt")"
  resolve_latest_text="$(cat "${work}/version.txt")"
  resolve_latest_version=""
  if [ "${resolve_latest_lines}" = "1" ]; then
    case "${resolve_latest_text}" in
      "rclone v"*)
        if resolve_latest_version="$(normalize_version "${resolve_latest_text#rclone }")" \
          && ! version_at_least "${resolve_latest_version}" "${MIN_VERSION}"; then
          resolve_latest_version=""
        fi
        ;;
    esac
  fi
  if [ -z "${resolve_latest_version}" ]; then
    # Quoted up to 120 bytes: a wrong answer may be a whole page.
    fail "${VERSION_URL} holds \"$(printf '%.120s' "${resolve_latest_text}")\", not one line" \
      "\"rclone v<version>\" naming a release at or above ${MIN_VERSION}; set version to a release"
  fi
  version="${resolve_latest_version}"
  log "read the newest release from ${VERSION_URL}: ${version}"
}

# Sets ${installed} to "true" when ${TARGET} already reports ${version}. An rclone that exits non-zero or prints
# anything else is replaced.
check_installed() {
  [ -f "${TARGET}" ] || return 0
  if ! check_installed_output="$(run_rclone "${TARGET}" version 2>/dev/null)"; then
    return 0
  fi
  if [ "$(printf '%s\n' "${check_installed_output}" | sed -n 1p)" = "rclone v${version}" ]; then
    log "rclone ${version} is already installed at ${TARGET}; leaving it unchanged"
    installed="true"
  fi
}

# Downloads the release's checksum list and upstream's key list into ${work}, and fails unless the list carries a good
# signature whose signer's primary key is ${SIGNING_FINGERPRINT}. Writes the text that signature covers to
# ${work}/signed: lines outside the signature block are not covered, so the list itself is never read for checksums.
# The keyring lives in ${work}; no option weakens GnuPG's checks (openspec/specs/rclone/spec.md, "rclone signing key
# strength").
verify_checksum_list() {
  verify_checksum_list_url="${DOWNLOADS}/v${version}/${CHECKSUMS}"
  fetch --output "${work}/${CHECKSUMS}" "${verify_checksum_list_url}" \
    || fail "cannot download ${verify_checksum_list_url}; check that release v${version} exists" \
      "and that downloads.rclone.org is reachable"
  log "downloaded ${verify_checksum_list_url}"
  fetch --output "${work}/KEYS" "${KEYS_URL}" \
    || fail "cannot download ${KEYS_URL}; check network access to rclone.org"
  log "downloaded ${KEYS_URL}"

  # The key list is turned into a keyring file and used in place, not imported: importing starts gpg-agent, which the
  # minimal gpg packages of Debian and Alpine do not include, and verifying needs no agent.
  mkdir -m 700 "${work}/gnupg"
  gpg --batch --homedir "${work}/gnupg" --output "${work}/keys.gpg" --dearmor "${work}/KEYS" \
    2>"${work}/gpg-keys.log" \
    || fail "cannot read the keys from ${KEYS_URL}: $(cat "${work}/gpg-keys.log")"
  if ! gpg --batch --homedir "${work}/gnupg" --no-default-keyring --keyring "${work}/keys.gpg" \
    --status-file "${work}/gpg-status" --output "${work}/signed" --decrypt "${work}/${CHECKSUMS}" \
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
        "not by the release key ${SIGNING_FINGERPRINT}; see https://rclone.org/release_signing/"
  done
  log "verified the signature of ${CHECKSUMS} by ${SIGNING_FINGERPRINT}"
}

# Downloads the archive and fails unless the signed text holds exactly one entry for it and its SHA-256 digest equals
# that entry.
download_archive() {
  archive="rclone-v${version}-linux-${arch}.zip"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/signed" >"${work}/archive.sha256"
  download_archive_entries="$(awk 'END { print NR }' "${work}/archive.sha256")"
  # No entry means the release publishes no archive for this architecture, or that its entry lies outside the signed
  # text; several mean a list that cannot be trusted to name the archive.
  [ "${download_archive_entries}" != "0" ] \
    || fail "verification failed: the signed ${CHECKSUMS} of release v${version} holds no entry for ${archive};" \
      "set version to a release that has an archive for linux ${arch}"
  [ "${download_archive_entries}" = "1" ] \
    || fail "verification failed: the signed ${CHECKSUMS} of release v${version} holds" \
      "${download_archive_entries} entries for ${archive}, expected exactly one"

  download_archive_url="${DOWNLOADS}/v${version}/${archive}"
  fetch --output "${work}/${archive}" "${download_archive_url}" \
    || fail "cannot download ${download_archive_url}; check that release v${version} has an archive for linux ${arch}"
  log "downloaded ${download_archive_url}"
  # Short option: BusyBox sha256sum has no long ones.
  (cd "${work}" && sha256sum -c archive.sha256) \
    || fail "verification failed: ${archive} does not match its entry in the signed ${CHECKSUMS};" \
      "retry the build, and set version to another release if it persists"
}

# Extracts rclone from the archive and stages it next to ${TARGET}, checking that it reports ${version}.
stage_binary() {
  stage_binary_member="rclone-v${version}-linux-${arch}/rclone"
  mkdir "${work}/extract"
  unzip -q -o "${work}/${archive}" "${stage_binary_member}" -d "${work}/extract" \
    || fail "cannot extract ${stage_binary_member} from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [ ! -f "${work}/extract/${stage_binary_member}" ] || [ -L "${work}/extract/${stage_binary_member}" ]; then
    fail "${archive} does not hold ${stage_binary_member} as a regular file; set version to another release"
  fi
  mkdir -p "${TARGET%/*}"
  staged="$(mktemp "${TARGET%/*}/${STAGING_NAME}")"
  cp "${work}/extract/${stage_binary_member}" "${staged}"
  chmod 0755 "${staged}"
  if ! stage_binary_output="$(run_rclone "${staged}" version 2>&1)" \
    || [ "$(printf '%s\n' "${stage_binary_output}" | sed -n 1p)" != "rclone v${version}" ]; then
    fail "the rclone from ${archive} does not run or does not report v${version}:" \
      "$(printf '%s\n' "${stage_binary_output}" | sed -n 1p)"
  fi
}

# Creates directory $1 and each missing directory above it with mode 0755; existing ones keep their mode.
make_dir() {
  if [ -z "$1" ] || [ -d "$1" ]; then return 0; fi
  make_dir "${1%/*}"
  mkdir -m 755 "$1"
}

# Creates the directory of target $1 when it is missing and prints the path of a new staged file next to the target.
new_staged_file() {
  make_dir "${1%/*}"
  mktemp "${1%/*}/${STAGING_NAME}"
}

# Writes the completion script the rclone at $1 generates for shell $2 to staged file $3, readable by every user.
write_completion() {
  run_rclone "$1" completion "$2" - >"$3" || fail "rclone completion $2 failed; set version to another release"
  chmod 0644 "$3"
}

# Stages the three completion scripts from the rclone at $1. Each staged path is recorded before the file is written,
# so cleanup removes it whatever happens next.
stage_completions() {
  staged_bash="$(new_staged_file "${BASH_COMPLETION}")"
  write_completion "$1" bash "${staged_bash}"
  staged_zsh="$(new_staged_file "${ZSH_COMPLETION}")"
  write_completion "$1" zsh "${staged_zsh}"
  staged_fish="$(new_staged_file "${FISH_COMPLETION}")"
  write_completion "$1" fish "${staged_fish}"
}

# Renames every staged file over its target. Everything was staged first, so a failure before this point left every
# earlier file as it was.
activate() {
  if [ -n "${staged}" ]; then
    mv -f "${staged}" "${TARGET}"
    staged=""
    log "installed rclone ${version} from ${archive} to ${TARGET}"
  fi
  mv -f "${staged_bash}" "${BASH_COMPLETION}"
  staged_bash=""
  mv -f "${staged_zsh}" "${ZSH_COMPLETION}"
  staged_zsh=""
  mv -f "${staged_fish}" "${FISH_COMPLETION}"
  staged_fish=""
  log "wrote the completion scripts to ${BASH_COMPLETION}, ${ZSH_COMPLETION}, and ${FISH_COMPLETION}"
}

main() {
  validate_options
  detect_platform
  readonly VERSION INSTALLMOUNTDEPENDENCIES

  trap cleanup EXIT
  # dash does not run the EXIT trap when a signal ends the script; exiting from the signal's trap runs it, with the
  # status a shell reports for that signal.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  check_targets
  install_packages
  work="$(mktemp -d "${TMPDIR:-/tmp}/rclone-feature.XXXXXX")"
  mkdir -m 700 "${work}/home"
  if [ "${VERSION}" = "latest" ]; then resolve_latest; fi
  check_installed
  if [ "${installed}" = "true" ]; then
    stage_completions "${TARGET}"
  else
    verify_checksum_list
    download_archive
    stage_binary
    stage_completions "${staged}"
  fi
  activate
}

main "$@"
