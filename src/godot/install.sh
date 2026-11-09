#!/usr/bin/env bash
# Installs the standard build of the Godot editor from its GitHub release archive, verified against the release's
# SHA512-SUMS.txt, to /usr/local/bin/godot, with the font configuration library the editor loads at start. Installs
# nothing for a graphical session. Runs as root at image build time; the option `version` arrives as VERSION.
set -euo pipefail

readonly MIN_VERSION="4.2.2"
readonly MIN_MAJOR=4
readonly MIN_MINOR=2
readonly MIN_PATCH=2
readonly RELEASES="https://github.com/godotengine/godot/releases"
readonly LATEST_URL="${RELEASES}/latest"
readonly CHECKSUMS="SHA512-SUMS.txt"
readonly TARGET="/usr/local/bin/godot"
# The executable is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="${TARGET%/*}/.godot-feature.XXXXXX"
readonly WORK_TEMPLATE="${TMPDIR:-/tmp}/godot-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly FAMILIES="the Debian, Ubuntu, or Fedora family"
# The forms of the version option: MAJOR.MINOR or MAJOR.MINOR.PATCH without leading zeros, optionally with the
# "-stable" suffix upstream's tags carry. A pre-release gets its own message.
readonly STABLE_INPUT='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?(-stable)?$'
readonly PRERELEASE_INPUT='^[0-9]+\.[0-9]+(\.[0-9]+)?-(dev|alpha|beta|rc)[0-9]*$'
# A tag as upstream writes it, which never carries a zero patch; the latest-release link must name one.
readonly STABLE_TAG='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.[1-9][0-9]*)?-stable$'

VERSION="${VERSION-latest}"

version=""
tag=""
arch=""
pm=""
archive=""
executable=""
work=""
staged=""
installed="false"

log() {
  printf 'godot: %s\n' "$*"
}

fail() {
  printf 'godot: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged executable and the work directory on every exit, success or failure.
cleanup() {
  if [[ -n "${staged}" ]]; then rm --force "${staged}"; fi
  if [[ -n "${work}" ]]; then rm --recursive --force "${work}"; fi
}

# Runs curl over HTTPS only, including each redirect, with failing HTTP statuses as errors. --retry 3 handles a known
# failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Runs a Godot executable with HOME in the work directory and the XDG base directories unset, so it writes nothing
# into a real home.
run_isolated() {
  env --unset=XDG_CONFIG_HOME --unset=XDG_DATA_HOME --unset=XDG_CACHE_HOME HOME="${work}/home" "$@"
}

# Succeeds when $1, the output of `godot --version`, reports ${version} as an official stable build: the version,
# ".stable.official.", and a hexadecimal commit hash.
reports_version() {
  local expected="${version}.stable.official."
  [[ "$1" == "${expected}"* && "${1#"${expected}"}" =~ ^[0-9a-f]+$ ]]
}

# Succeeds when version $1 (MAJOR.MINOR[.PATCH], a missing patch counting as 0) is at or above MIN_VERSION.
meets_minimum() {
  local major="${1%%.*}"
  local rest="${1#*.}"
  local minor="${rest%%.*}"
  local patch=0
  if [[ "${rest}" == *.* ]]; then patch="${rest#*.}"; fi
  if (( major > MIN_MAJOR || (major == MIN_MAJOR && minor > MIN_MINOR)
    || (major == MIN_MAJOR && minor == MIN_MINOR && patch >= MIN_PATCH) )); then
    return 0
  fi
  return 1
}

# Fails unless VERSION is "latest" or a stable release at or above MIN_VERSION in an accepted form. Sets ${version}
# and ${tag} for an explicit release, and leaves them empty for "latest".
validate_options() {
  if [[ "${VERSION}" == latest ]]; then return 0; fi
  if [[ "${VERSION}" =~ ${PRERELEASE_INPUT} ]]; then
    fail "option version is \"${VERSION}\", a pre-release; only stable releases are accepted," \
      "so set version to latest or a stable release such as 4.6.3"
  fi
  if [[ ! "${VERSION}" =~ ${STABLE_INPUT} ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or a stable release MAJOR.MINOR or MAJOR.MINOR.PATCH" \
      "such as 4.6 or 4.6.3, with or without \"-stable\""
  fi
  # The selected version is MAJOR.MINOR[.PATCH] without the "-stable" suffix and without a zero patch.
  version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  if [[ -n "${BASH_REMATCH[4]}" && "${BASH_REMATCH[4]}" != 0 ]]; then version+=".${BASH_REMATCH[4]}"; fi
  if ! meets_minimum "${version}"; then
    fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
  fi
  tag="${version}-stable"
}

# Fails unless the machine is x86_64 or aarch64 and the image belongs to a supported family and has that family's
# package manager; sets ${arch} to upstream's archive name for the machine and ${pm}. Runs before VERSION becomes
# readonly: /etc/os-release assigns it too.
detect_platform() {
  local machine
  local os_id
  local os_id_like
  local family
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64) arch=x86_64 ;;
    aarch64) arch=arm64 ;;
    *) fail "unsupported architecture \"${machine}\"; use an x86_64 or aarch64 machine" ;;
  esac

  [[ -f /etc/os-release ]] \
    || fail "/etc/os-release is missing, so the distribution cannot be identified; use an image of ${FAMILIES}"
  # Read in subshells: os-release sets VERSION, which would overwrite the option.
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"

  # ID decides first, then each word of ID_LIKE in order. The two values are unquoted to split them into words, and
  # set -f keeps a word from expanding as a glob.
  set -f
  for family in ${os_id} ${os_id_like}; do
    case "${family}" in
      debian | ubuntu)
        pm=apt-get
        break
        ;;
      fedora)
        pm=dnf
        break
        ;;
      alpine)
        fail "distribution \"${os_id}\" uses the musl C library, but upstream's Godot builds need the GNU C library;" \
          "use an image of ${FAMILIES}"
        ;;
    esac
  done
  set +f
  [[ -n "${pm}" ]] \
    || fail "unsupported distribution \"${os_id}\" (ID_LIKE \"${os_id_like}\"); use an image of ${FAMILIES}"
  command -v "${pm}" >/dev/null 2>&1 \
    || fail "distribution \"${os_id}\" is in a supported family, but its package manager ${pm} is missing;" \
      "use an image that has ${pm}"
}

# Fails when ${TARGET} exists but is not a regular file: a rename over a directory would put the executable inside it,
# and a symbolic link may belong to another installation.
check_target() {
  if [[ -L "${TARGET}" || (-e "${TARGET}" && ! -f "${TARGET}") ]]; then
    fail "${TARGET} exists but is not a regular file; remove it before this feature runs"
  fi
}

# Installs what the image lacks of curl, unzip, and ca-certificates, which the install needs, and of the font
# configuration library, which the editor loads at start, then cleans the package manager's cache.
install_prerequisites() {
  local missing=()
  local command
  local status
  local linker_cache
  for command in curl unzip; do
    if ! command -v "${command}" >/dev/null 2>&1; then missing+=("${command}"); fi
  done
  case "${pm}" in
    apt-get)
      # Known failure mode: dpkg-query exits 1 for a package dpkg has no record of. Any failed query counts as not
      # installed.
      if ! status="$(dpkg-query --show --showformat '${Status}' ca-certificates 2>/dev/null)"; then status=""; fi
      if [[ "${status}" != *'install ok installed'* ]]; then missing+=(ca-certificates); fi
      ;;
    dnf)
      if ! rpm --query ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      ;;
  esac
  # The library is looked up the way the editor loads it, through the dynamic linker's cache, whichever package
  # provides it.
  linker_cache="$(ldconfig --print-cache)"
  if [[ ! "${linker_cache}" =~ (^|[[:space:]])libfontconfig\.so\.1[[:space:]] ]]; then
    case "${pm}" in
      apt-get) missing+=(libfontconfig1) ;;
      dnf) missing+=(fontconfig) ;;
    esac
  fi
  if (( ${#missing[@]} == 0 )); then return 0; fi

  log "installing missing prerequisites with ${pm}: ${missing[*]}"
  case "${pm}" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update \
        || fail "apt-get update failed; check the image's package repositories and network access"
      DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "${missing[@]}" \
        || fail "apt-get install failed; check the image's package repositories and network access"
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    dnf)
      dnf install --assumeyes "${missing[@]}" \
        || fail "dnf install failed; check the image's package repositories and network access"
      dnf clean all
      ;;
  esac
}

# Sets ${tag} and ${version} to the release the latest-release link redirects to, read without following the
# redirect. The tag must be a stable tag as upstream writes it, at or above MIN_VERSION, and is used unchanged.
resolve_latest() {
  local location
  location="$(fetch --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")" \
    || fail "cannot read ${LATEST_URL}; check network access to github.com, or set version to a release"
  [[ -n "${location}" ]] || fail "${LATEST_URL} did not redirect to a release; set version to a release"
  log "read the latest release from ${LATEST_URL}: ${location}"
  # The tag is the last path segment of the redirect target, without a query, a fragment, or a trailing slash.
  tag="${location%%[?#]*}"
  tag="${tag%/}"
  tag="${tag##*/}"
  [[ "${tag}" =~ ${STABLE_TAG} ]] \
    || fail "the latest release is \"${tag}\", which is not a stable release tag; set version to a release"
  version="${tag%-stable}"
  if ! meets_minimum "${version}"; then
    fail "the latest release is \"${tag}\", below the minimum ${MIN_VERSION}; set version to a release"
  fi
}

# Sets ${installed} to "true" when ${TARGET} already reports ${version} as an official stable build. A godot that exits
# non-zero or prints anything else is replaced.
check_installed() {
  local output
  [[ -f "${TARGET}" ]] || return 0
  if ! output="$(run_isolated "${TARGET}" --version 2>/dev/null)"; then return 0; fi
  if reports_version "${output}"; then
    log "Godot ${version} is already installed at ${TARGET}; leaving it unchanged"
    installed="true"
  fi
}

# Downloads the release's checksum list and then its archive into ${work}, logging each final URL without its query
# string (GitHub's asset host signs the URL with a short-lived token) so a host change shows in the build log. Fails
# unless the list holds exactly one entry for the archive and the archive's SHA-512 digest equals that entry. Upstream
# signs nothing, so the list relies on TLS alone (openspec/specs/godot/spec.md, "Godot release metadata trust").
download_and_verify() {
  local url="${RELEASES}/download/${tag}"
  local final
  local entries
  archive="Godot_v${tag}_linux.${arch}.zip"
  executable="Godot_v${tag}_linux.${arch}"

  # The list is fetched first: upstream uploads it last, so a build while a release is still uploading fails here.
  final="$(fetch --location --output "${work}/${CHECKSUMS}" --write-out '%{url_effective}' "${url}/${CHECKSUMS}")" \
    || fail "cannot download ${url}/${CHECKSUMS}; check that release ${tag} exists and has finished uploading," \
      "and that github.com is reachable"
  log "downloaded ${url}/${CHECKSUMS} to ${work}/${CHECKSUMS} (final URL: ${final%%\?*})"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/${CHECKSUMS}" >"${work}/archive.sha512"
  entries="$(awk 'END { print NR }' "${work}/archive.sha512")"
  # No entry means the release publishes no archive for this architecture; several mean a checksum list that cannot
  # be trusted to name the archive.
  [[ "${entries}" != 0 ]] \
    || fail "verification failed: ${CHECKSUMS} of release ${tag} holds no entry for ${archive}," \
      "so the release has no archive for linux ${arch}; set version to a release that has one"
  [[ "${entries}" == 1 ]] \
    || fail "verification failed: ${CHECKSUMS} of release ${tag} holds ${entries} entries for ${archive}," \
      "expected exactly one; retry the build, and set version to another release if it persists"

  final="$(fetch --location --output "${work}/${archive}" --write-out '%{url_effective}' "${url}/${archive}")" \
    || fail "cannot download ${url}/${archive}; check that release ${tag} has an archive for linux ${arch}"
  log "downloaded ${url}/${archive} to ${work}/${archive} (final URL: ${final%%\?*})"
  (cd "${work}" && sha512sum --check --quiet archive.sha512) \
    || fail "verification failed: ${archive} does not match its entry in ${CHECKSUMS} of release ${tag};" \
      "retry the build, and set version to another release if it persists"
}

# Extracts the executable into ${work}/extract after checking that it is the archive's one and only entry.
extract_executable() {
  local entries
  entries="$(unzip -Z1 "${work}/${archive}")" \
    || fail "cannot list the entries of ${archive}; set version to another release"
  [[ "${entries}" == "${executable}" ]] \
    || fail "${archive} does not hold exactly one entry, ${executable}; set version to another release"
  mkdir "${work}/extract"
  unzip -q "${work}/${archive}" "${executable}" -d "${work}/extract" \
    || fail "cannot extract ${executable} from ${archive}; set version to another release"
  # Only a regular file is installed: cp would follow a symbolic link out of the work directory.
  if [[ ! -f "${work}/extract/${executable}" || -L "${work}/extract/${executable}" ]]; then
    fail "${archive} does not hold ${executable} as a regular file; set version to another release"
  fi
}

# Stages the executable next to ${TARGET}, checks that it runs and reports ${version}, and renames it over the target,
# so the target is replaced in one step and only by an executable that runs on this image.
install_executable() {
  local output
  mkdir --parents "${TARGET%/*}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work}/extract/${executable}" "${staged}"
  chmod 0755 "${staged}"
  if ! output="$(run_isolated "${staged}" --version 2>"${work}/version.stderr")" || ! reports_version "${output}"; then
    cat "${work}/version.stderr" >&2
    fail "the version check failed: ${executable} from ${archive} printed \"${output}\" instead of" \
      "${version}.stable.official.<hash>; check that the image's C library is recent enough for this release" \
      "(glibc 2.28 for 4.2 to 4.7), or set version to another release"
  fi
  mv --force "${staged}" "${TARGET}"
  staged=""
  log "installed Godot ${version} from ${archive} to ${TARGET}"
}

main() {
  validate_options
  detect_platform
  readonly VERSION

  trap cleanup EXIT
  check_target
  install_prerequisites
  work="$(mktemp --directory "${WORK_TEMPLATE}")"
  mkdir --mode 0700 "${work}/home"
  if [[ "${VERSION}" == latest ]]; then resolve_latest; fi
  check_installed
  if [[ "${installed}" == false ]]; then
    download_and_verify
    extract_executable
    install_executable
  fi
}

main "$@"
