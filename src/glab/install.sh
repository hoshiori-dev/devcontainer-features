#!/bin/sh
# Installs the GitLab CLI (glab) from its GitLab release archive, verified against the release's checksums.txt, to
# /usr/local/bin/glab. Runs as root at image build time; the option `version` arrives as VERSION. Configures no
# authentication and writes nothing under any home directory.
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly MIN_VERSION="1.47.0"
readonly RELEASES="https://gitlab.com/gitlab-org/cli/-/releases"
readonly LATEST_URL="${RELEASES}/permalink/latest"
readonly TARGET="/usr/local/bin/glab"
# The binary is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="${TARGET%/*}/.glab-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly FAMILIES="the Debian, Ubuntu, Fedora, or Alpine family"

VERSION="${VERSION-latest}"

version=""
arch=""
pm=""
archive=""
work=""
staged=""

log() {
  printf 'glab: %s\n' "$*"
}

fail() {
  printf 'glab: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged binary and the work directory on every exit, success or failure.
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

# Runs curl over HTTPS only, including each redirect, with failing HTTP statuses as errors. --retry 3 handles a known
# failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Fails unless VERSION is "latest" or a release version at or above MIN_VERSION. Sets ${version} to the release
# version without its leading "v", and leaves it empty for "latest".
validate_options() {
  if [ "${VERSION}" = "latest" ]; then return 0; fi
  if ! version="$(normalize_version "${VERSION}")"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release version MAJOR.MINOR.PATCH such as 1.120.0, with or without a leading \"v\""
  fi
  if ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
  fi
}

# Fails unless the machine is x86_64 or aarch64 and the image belongs to a supported family and has that family's
# package manager; sets ${arch} and ${pm}. Runs before VERSION becomes readonly: /etc/os-release assigns it too.
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

# Installs what the image lacks of git, which glab needs at run time, and of curl, tar, and ca-certificates, which
# the install needs, and cleans the package manager's cache. The missing packages are this function's positional
# parameters.
install_prerequisites() {
  set --
  for install_prerequisites_command in git curl tar; do
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
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
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
    || fail "cannot read ${LATEST_URL}; check network access to gitlab.com, or set version to a release"
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

# Ends the install with status 0 when ${TARGET} already reports ${version} in an output format glab has used since
# 1.47.0. A glab that exits non-zero or prints anything else is replaced. The glab run is isolated from the image:
# temporary configuration, no update check, no telemetry.
skip_when_installed() {
  [ -f "${TARGET}" ] || return 0
  mkdir --mode 700 "${work}/config"
  if ! skip_when_installed_output="$(
    GLAB_CONFIG_DIR="${work}/config" GLAB_CHECK_UPDATE=false CHECK_UPDATE=false GLAB_SEND_TELEMETRY=false \
      "${TARGET}" --version 2>/dev/null
  )"; then
    return 0
  fi
  case "${skip_when_installed_output}" in
    "glab ${version} ("* | "Current glab version: ${version}" | "Current glab version: ${version} ("*)
      log "glab ${version} is already installed at ${TARGET}; leaving it unchanged"
      exit 0
      ;;
  esac
}

# Downloads the release's checksums.txt and then its archive into ${work}, logging each final URL so a host change
# shows in the build log. Fails unless checksums.txt holds exactly one entry for the archive and the archive's
# SHA-256 digest equals that entry.
download_and_verify() {
  archive="glab_${version}_linux_${arch}.tar.gz"
  download_and_verify_url="${RELEASES}/v${version}/downloads"

  download_and_verify_final="$(fetch --location --output "${work}/checksums.txt" --write-out '%{url_effective}' \
    "${download_and_verify_url}/checksums.txt")" \
    || fail "cannot download ${download_and_verify_url}/checksums.txt;" \
      "check that release v${version} exists and that gitlab.com is reachable"
  log "downloaded ${download_and_verify_url}/checksums.txt to ${work}/checksums.txt" \
    "(final URL: ${download_and_verify_final})"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/checksums.txt" >"${work}/archive.sha256"
  download_and_verify_entries="$(awk 'END { print NR }' "${work}/archive.sha256")"
  [ "${download_and_verify_entries}" = "1" ] \
    || fail "verification failed: checksums.txt of release v${version} holds ${download_and_verify_entries} entries" \
      "for ${archive}, expected exactly one;" \
      "retry the build, and set version to another release if it persists"

  download_and_verify_final="$(fetch --location --output "${work}/${archive}" --write-out '%{url_effective}' \
    "${download_and_verify_url}/${archive}")" \
    || fail "cannot download ${download_and_verify_url}/${archive};" \
      "check that release v${version} has an archive for linux ${arch}"
  log "downloaded ${download_and_verify_url}/${archive} to ${work}/${archive}" \
    "(final URL: ${download_and_verify_final})"
  (cd "${work}" && sha256sum -c archive.sha256) \
    || fail "verification failed: ${archive} does not match its entry in checksums.txt;" \
      "retry the build, and set version to another release if it persists"
}

# Extracts bin/glab from the archive into ${work}/extract.
extract_binary() {
  mkdir "${work}/extract"
  tar --extract --gzip --file "${work}/${archive}" --directory "${work}/extract" bin/glab \
    || fail "cannot extract bin/glab from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [ ! -f "${work}/extract/bin/glab" ] || [ -L "${work}/extract/bin/glab" ]; then
    fail "${archive} does not hold bin/glab as a regular file; set version to another release"
  fi
}

# Stages the binary next to ${TARGET} and renames it over the target, so the target is replaced in one step.
install_binary() {
  mkdir --parents "${TARGET%/*}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work}/extract/bin/glab" "${staged}"
  chmod 0755 "${staged}"
  mv --force "${staged}" "${TARGET}"
  staged=""
  log "installed glab ${version} from ${archive} to ${TARGET}"
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

  install_prerequisites
  work="$(mktemp --directory "${TMPDIR:-/tmp}/glab-feature.XXXXXX")"
  if [ "${VERSION}" = "latest" ]; then resolve_latest; fi
  skip_when_installed
  download_and_verify
  extract_binary
  install_binary
}

main "$@"
