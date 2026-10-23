#!/bin/sh
# Installs act, which runs GitHub Actions workflows locally, from its GitHub release archive, verified against the
# release's checksum file, to /usr/local/bin/act. With defaultImage other than "none", also writes the remote user's
# act configuration file <home>/.config/act/actrc with the runner images act's own first-run prompt selects. Installs
# no container engine. Runs as root at image build time; options arrive as environment variables:
#   version: VERSION
#   defaultImage: DEFAULTIMAGE
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly MIN_VERSION="0.2.23"
readonly RELEASES="https://github.com/nektos/act/releases"
readonly LATEST_URL="${RELEASES}/latest"
readonly CHECKSUMS="checksums.txt"
readonly TARGET="/usr/local/bin/act"
# The binary is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="${TARGET%/*}/.act-feature.XXXXXX"
# Relative to the remote user's home: the first location act reads when XDG_CONFIG_HOME is unset.
readonly CONFIG_DIR_IN_HOME=".config/act"
readonly CONFIG_NAME="actrc"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly FAMILIES="the Debian, Ubuntu, Fedora, or Alpine family"

VERSION="${VERSION-latest}"
DEFAULTIMAGE="${DEFAULTIMAGE-none}"

version=""
arch=""
pm=""
archive=""
work=""
staged=""
staged_config=""
installed="false"
config_user=""
config_uid=""
config_gid=""
config_home=""

log() {
  printf 'act: %s\n' "$*"
}

fail() {
  printf 'act: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged binary, the staged configuration file, and the work directory on every exit, success or failure.
# Short options: BusyBox rm has no long ones.
cleanup() {
  if [ -n "${staged}" ]; then rm -f "${staged}"; fi
  if [ -n "${staged_config}" ]; then rm -f "${staged_config}"; fi
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

# Runs curl over HTTPS only, including each redirect, with failing HTTP statuses as errors. --retry 3 handles a known
# failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Fails unless VERSION is "latest" or a release version at or above MIN_VERSION, and DEFAULTIMAGE is one of its
# values. Sets ${version} to the release version without its leading "v", and leaves it empty for "latest".
validate_options() {
  case "${DEFAULTIMAGE}" in
    none | medium | large) ;;
    *) fail "option defaultImage is \"${DEFAULTIMAGE}\"; use \"none\", \"medium\", or \"large\"" ;;
  esac
  if [ "${VERSION}" = "latest" ]; then return 0; fi
  if ! version="$(normalize_version "${VERSION}")"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release version MAJOR.MINOR.PATCH such as 0.2.89, with or without a leading \"v\""
  fi
  if ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
  fi
}

# Fails unless the machine is x86_64 or aarch64 and the image belongs to a supported family and has that family's
# package manager; sets ${arch} to upstream's archive name for the machine and ${pm}. Runs before VERSION becomes
# readonly: /etc/os-release assigns it too.
detect_platform() {
  detect_platform_machine="$(uname -m)"
  case "${detect_platform_machine}" in
    x86_64) arch=x86_64 ;;
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
        break
        ;;
      fedora)
        pm=dnf
        break
        ;;
      alpine)
        pm=apk
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

# Fails when ${TARGET} exists but is not a regular file: a rename over a directory would put the binary inside it and
# the install would still report success.
check_target() {
  if [ -e "${TARGET}" ] || [ -L "${TARGET}" ]; then
    if [ ! -f "${TARGET}" ] || [ -L "${TARGET}" ]; then
      fail "${TARGET} exists but is not a regular file; remove it or install act elsewhere"
    fi
  fi
}

# Sets ${config_user}, ${config_uid}, ${config_gid}, and ${config_home} for the remote user, or root when no remote
# user is set, and fails when anything on the configuration file's path exists but is not what the install would
# create there: the path is written as root, so a symbolic link or a file in the way is never followed or replaced.
check_config_path() {
  config_user="${_REMOTE_USER:-root}"
  # Read from /etc/passwd with awk: BusyBox images may lack getent.
  check_config_path_entry="$(awk -F: -v user="${config_user}" '$1 == user { print $3 ":" $4 ":" $6; exit }' \
    /etc/passwd)"
  [ -n "${check_config_path_entry}" ] \
    || fail "remote user \"${config_user}\" is not in /etc/passwd; create the user before this feature runs," \
      "or set defaultImage to \"none\""
  config_uid="${check_config_path_entry%%:*}"
  check_config_path_rest="${check_config_path_entry#*:}"
  config_gid="${check_config_path_rest%%:*}"
  config_home="${_REMOTE_USER_HOME:-${check_config_path_rest#*:}}"
  case "${config_home}" in
    /?*) ;;
    *) fail "the home directory of \"${config_user}\" is \"${config_home}\"; give the user an absolute home" ;;
  esac
  if [ ! -d "${config_home}" ] || [ -L "${config_home}" ]; then
    fail "the home directory ${config_home} of \"${config_user}\" is missing or not a directory;" \
      "create it before this feature runs, or set defaultImage to \"none\""
  fi

  check_config_path_dir="${config_home}"
  for check_config_path_part in .config act; do
    check_config_path_dir="${check_config_path_dir}/${check_config_path_part}"
    if [ -L "${check_config_path_dir}" ] \
      || { [ -e "${check_config_path_dir}" ] && [ ! -d "${check_config_path_dir}" ]; }; then
      fail "${check_config_path_dir} exists but is not a directory; move it, or set defaultImage to \"none\""
    fi
  done
  check_config_path_file="${config_home}/${CONFIG_DIR_IN_HOME}/${CONFIG_NAME}"
  if [ -L "${check_config_path_file}" ] \
    || { [ -e "${check_config_path_file}" ] && [ ! -f "${check_config_path_file}" ]; }; then
    fail "${check_config_path_file} exists but is not a regular file; move it, or set defaultImage to \"none\""
  fi
}

# Installs what the image lacks of curl, tar, and ca-certificates, which the install needs, and cleans the package
# manager's cache. The missing packages are this function's positional parameters.
install_prerequisites() {
  set --
  for install_prerequisites_command in curl tar; do
    if ! command -v "${install_prerequisites_command}" >/dev/null 2>&1; then
      set -- "$@" "${install_prerequisites_command}"
    fi
  done
  case "${pm}" in
    apt-get)
      # Known failure mode: dpkg-query exits 1 for a package dpkg has no record of. Any failed query counts as not
      # installed.
      if ! install_prerequisites_status="$(
        dpkg-query --show --showformat '${Status}' ca-certificates 2>/dev/null
      )"; then
        install_prerequisites_status=""
      fi
      case "${install_prerequisites_status}" in
        *'install ok installed'*) ;;
        *) set -- "$@" ca-certificates ;;
      esac
      ;;
    dnf)
      if ! rpm --query ca-certificates >/dev/null 2>&1; then set -- "$@" ca-certificates; fi
      ;;
    apk)
      if ! apk info --installed ca-certificates >/dev/null 2>&1; then set -- "$@" ca-certificates; fi
      ;;
  esac
  if [ "$#" -eq 0 ]; then return 0; fi

  log "installing missing prerequisites with ${pm}: $*"
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

# Sets ${version} to the release the latest-release link redirects to, read without following the redirect.
resolve_latest() {
  resolve_latest_location="$(fetch --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")" \
    || fail "cannot read ${LATEST_URL}; check network access to github.com, or set version to a release"
  [ -n "${resolve_latest_location}" ] \
    || fail "${LATEST_URL} did not redirect to a release; set version to a release"
  log "read the latest release from ${LATEST_URL}: ${resolve_latest_location}"
  # The Location header may be absolute or relative, and curl prints the URL it resolves to. The tag is the last
  # path segment of that URL, without a query, a fragment, or a trailing slash.
  resolve_latest_tag="${resolve_latest_location%%[?#]*}"
  resolve_latest_tag="${resolve_latest_tag%/}"
  resolve_latest_tag="${resolve_latest_tag##*/}"
  if ! version="$(normalize_version "${resolve_latest_tag}")"; then
    fail "the latest release is \"${resolve_latest_tag}\", which is not a release version MAJOR.MINOR.PATCH;" \
      "set version to a release"
  fi
  if ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "the latest release is \"${resolve_latest_tag}\", below the minimum ${MIN_VERSION};" \
      "set version to a release"
  fi
}

# Sets ${installed} to "true" when ${TARGET} already reports ${version}. An act that exits non-zero or prints
# anything else is replaced. The run is isolated from the image: act creates the parent of its configuration file
# under XDG_CONFIG_HOME, which points into the work directory, and ACT_DISABLE_VERSION_CHECK keeps it offline.
check_installed() {
  [ -f "${TARGET}" ] || return 0
  mkdir -m 700 "${work}/home"
  if ! check_installed_output="$(HOME="${work}/home" XDG_CONFIG_HOME="${work}/home/.config" \
    ACT_DISABLE_VERSION_CHECK=1 "${TARGET}" --version 2>/dev/null)"; then
    return 0
  fi
  if [ "${check_installed_output}" = "act version ${version}" ]; then
    log "act ${version} is already installed at ${TARGET}; leaving it unchanged"
    installed="true"
  fi
}

# Downloads the release's checksum file and then its archive into ${work}, logging each final URL without its query
# string (GitHub's asset host signs the URL with a short-lived token) so a host change shows in the build log. Fails
# unless the checksum file holds exactly one entry for the archive and the archive's SHA-256 digest equals that entry.
# Upstream signs nothing, so the checksum file relies on TLS alone (openspec/specs/act/spec.md, "act release metadata
# trust").
download_and_verify() {
  archive="act_Linux_${arch}.tar.gz"
  download_and_verify_url="${RELEASES}/download/v${version}"

  download_and_verify_final="$(fetch --location --output "${work}/${CHECKSUMS}" --write-out '%{url_effective}' \
    "${download_and_verify_url}/${CHECKSUMS}")" \
    || fail "cannot download ${download_and_verify_url}/${CHECKSUMS};" \
      "check that release v${version} exists and that github.com is reachable"
  log "downloaded ${download_and_verify_url}/${CHECKSUMS} to ${work}/${CHECKSUMS}" \
    "(final URL: ${download_and_verify_final%%\?*})"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/${CHECKSUMS}" >"${work}/archive.sha256"
  download_and_verify_entries="$(awk 'END { print NR }' "${work}/archive.sha256")"
  # No entry means the release publishes no archive for this architecture; several mean a checksum list that cannot
  # be trusted to name the archive.
  [ "${download_and_verify_entries}" != "0" ] \
    || fail "verification failed: the checksum file of release v${version} holds no entry for ${archive}," \
      "so the release has no archive for linux ${arch}; set version to a release that has one"
  [ "${download_and_verify_entries}" = "1" ] \
    || fail "verification failed: the checksum file of release v${version} holds" \
      "${download_and_verify_entries} entries for ${archive}, expected exactly one;" \
      "retry the build, and set version to another release if it persists"

  download_and_verify_final="$(fetch --location --output "${work}/${archive}" --write-out '%{url_effective}' \
    "${download_and_verify_url}/${archive}")" \
    || fail "cannot download ${download_and_verify_url}/${archive};" \
      "check that release v${version} has an archive for linux ${arch}"
  log "downloaded ${download_and_verify_url}/${archive} to ${work}/${archive}" \
    "(final URL: ${download_and_verify_final%%\?*})"
  # Short option: BusyBox sha256sum has no long ones.
  (cd "${work}" && sha256sum -c archive.sha256) \
    || fail "verification failed: ${archive} does not match its entry in ${CHECKSUMS};" \
      "retry the build, and set version to another release if it persists"
}

# Extracts act from the archive into ${work}/extract.
extract_binary() {
  mkdir "${work}/extract"
  tar -x -z -f "${work}/${archive}" -C "${work}/extract" act \
    || fail "cannot extract act from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [ ! -f "${work}/extract/act" ] || [ -L "${work}/extract/act" ]; then
    fail "${archive} does not hold act as a regular file; set version to another release"
  fi
}

# Stages the binary next to ${TARGET} and renames it over the target, so the target is replaced in one step.
install_binary() {
  mkdir -p "${TARGET%/*}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work}/extract/act" "${staged}"
  chmod 0755 "${staged}"
  mv -f "${staged}" "${TARGET}"
  staged=""
  log "installed act ${version} from ${archive} to ${TARGET}"
}

# Writes the lines act's first-run prompt writes for ${DEFAULTIMAGE} to the remote user's configuration file. Each
# missing directory on the way is created and given to the remote user; existing ones keep their owner. The file is
# staged in its own directory and renamed over any earlier one.
write_config() {
  case "${DEFAULTIMAGE}" in
    medium) write_config_tag="act" ;;
    large) write_config_tag="full" ;;
  esac
  write_config_dir="${config_home}"
  for write_config_part in .config act; do
    write_config_dir="${write_config_dir}/${write_config_part}"
    if [ ! -d "${write_config_dir}" ]; then
      mkdir -m 755 "${write_config_dir}"
      chown "${config_uid}:${config_gid}" "${write_config_dir}"
    fi
  done
  write_config_file="${write_config_dir}/${CONFIG_NAME}"
  staged_config="$(mktemp "${write_config_dir}/.${CONFIG_NAME}-feature.XXXXXX")"
  for write_config_label in latest 22.04 20.04 18.04; do
    printf -- '-P ubuntu-%s=catthehacker/ubuntu:%s-%s\n' \
      "${write_config_label}" "${write_config_tag}" "${write_config_label}"
  done >"${staged_config}"
  chmod 0644 "${staged_config}"
  chown "${config_uid}:${config_gid}" "${staged_config}"
  mv -f "${staged_config}" "${write_config_file}"
  staged_config=""
  log "wrote the ${DEFAULTIMAGE} runner images to ${write_config_file} for \"${config_user}\""
}

main() {
  validate_options
  detect_platform
  readonly VERSION DEFAULTIMAGE

  trap cleanup EXIT
  # dash does not run the EXIT trap when a signal ends the script; exiting from the signal's trap runs it, with the
  # status a shell reports for that signal.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  check_target
  if [ "${DEFAULTIMAGE}" != "none" ]; then check_config_path; fi
  install_prerequisites
  work="$(mktemp -d "${TMPDIR:-/tmp}/act-feature.XXXXXX")"
  if [ "${VERSION}" = "latest" ]; then resolve_latest; fi
  check_installed
  if [ "${installed}" = "false" ]; then
    download_and_verify
    extract_binary
    install_binary
  fi
  if [ "${DEFAULTIMAGE}" != "none" ]; then write_config; fi
}

main "$@"
