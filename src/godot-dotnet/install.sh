#!/usr/bin/env bash
# Installs the .NET build of the Godot editor from its GitHub release archive, verified against the release's
# SHA512-SUMS.txt, into a release directory under /opt/godot-dotnet with /usr/local/bin/godot linked to it, and the
# font configuration library the editor loads at start. The .NET SDK comes from the dotnet feature this feature depends
# on. Installs nothing for a graphical session. Runs as root at image build time; the option `version` arrives as
# VERSION.
set -euo pipefail

readonly MIN_VERSION="4.2.2"
readonly MIN_MAJOR=4
readonly MIN_MINOR=2
readonly MIN_PATCH=2
readonly RELEASES="https://github.com/godotengine/godot/releases"
readonly LATEST_URL="${RELEASES}/latest"
readonly CHECKSUMS="SHA512-SUMS.txt"
readonly LINK="/usr/local/bin/godot"
readonly INSTALL_ROOT="/opt/godot-dotnet"
readonly MARKER_NAME=".devcontainer-feature-godot-dotnet"
readonly MARKER="${INSTALL_ROOT}/${MARKER_NAME}"
# The link this feature owns points at the executable named godot in one release directory under INSTALL_ROOT.
readonly OWN_LINK_TARGET='^/opt/godot-dotnet/([^/]+)/godot$'
# The temporary link is made next to LINK, so renaming it over LINK is one step on one file system.
readonly LINK_TEMPLATE="${LINK%/*}/.godot-dotnet-feature.XXXXXX"
readonly WORK_TEMPLATE="${TMPDIR:-/tmp}/godot-dotnet-feature.XXXXXX"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly FAMILIES="the Debian or Ubuntu family, which the dotnet feature supports"
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
archive=""
top=""
executable=""
work=""
# The release directory being staged; cleared once the link points into it.
staged=""
# The temporary link; cleared once it has been renamed over LINK.
temp_link=""
# "true" when this run created INSTALL_ROOT, so a failure before the switch removes it again.
created_root="false"
installed="false"

log() {
  printf 'godot-dotnet: %s\n' "$*"
}

fail() {
  printf 'godot-dotnet: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary link, an unswitched release directory, an INSTALL_ROOT this run created but did not switch to,
# and the work directory on every exit, success or failure.
cleanup() {
  if [[ -n "${temp_link}" ]]; then rm --force "${temp_link}"; fi
  if [[ -n "${staged}" ]]; then rm --recursive --force "${staged}"; fi
  if [[ "${created_root}" == true ]]; then rm --recursive --force "${INSTALL_ROOT}"; fi
  if [[ -n "${work}" ]]; then rm --recursive --force "${work}"; fi
}

# Runs curl over HTTPS only, including each redirect, with failing HTTP statuses as errors. --retry 6 handles a known
# failure mode: a transient network error or a 5xx answer, such as the bursts of 504 that GitHub's release downloads
# return at times; curl waits 1, 2, 4, ... seconds between tries, about a minute in all.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 6 "$@"
}

# Runs a Godot executable with HOME in the work directory and the XDG base directories unset, so it writes nothing
# into a real home.
run_isolated() {
  env --unset=XDG_CONFIG_HOME --unset=XDG_DATA_HOME --unset=XDG_CACHE_HOME HOME="${work}/home" "$@"
}

# Succeeds when $1, the output of `godot --version`, reports ${version} as an official stable .NET build: the version,
# ".stable.mono.official.", and a hexadecimal commit hash.
reports_version() {
  local expected="${version}.stable.mono.official."
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

# Fails unless the machine is x86_64 or aarch64 and the image belongs to the Debian or Ubuntu family and has apt-get;
# sets ${arch} to upstream's archive name for the machine. Runs before VERSION becomes readonly: /etc/os-release
# assigns it too.
detect_platform() {
  local machine
  local os_id
  local os_id_like
  local family
  local supported="false"
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
        supported="true"
        break
        ;;
      alpine)
        fail "distribution \"${os_id}\" uses the musl C library, but upstream's Godot builds need the GNU C library;" \
          "use an image of ${FAMILIES}"
        ;;
    esac
  done
  set +f
  [[ "${supported}" == true ]] \
    || fail "unsupported distribution \"${os_id}\" (ID_LIKE \"${os_id_like}\"); use an image of ${FAMILIES}"
  command -v apt-get >/dev/null 2>&1 \
    || fail "distribution \"${os_id}\" is in a supported family, but its package manager apt-get is missing;" \
      "use an image that has apt-get"
}

# Fails, leaving both paths as they are, unless ${LINK} is absent or a link this feature made and ${INSTALL_ROOT} is
# absent or a directory holding this feature's root-owned marker.
check_paths() {
  local target
  if [[ -L "${LINK}" ]]; then
    target="$(readlink "${LINK}")"
    if [[ ! "${target}" =~ ${OWN_LINK_TARGET} || "${BASH_REMATCH[1]}" == . || "${BASH_REMATCH[1]}" == .. ]]; then
      fail "${LINK} is a symbolic link to \"${target}\", which this feature did not create; remove it before this" \
        "feature runs"
    fi
  elif [[ -f "${LINK}" ]]; then
    fail "${LINK} is a regular file, as the godot feature or another installation provides it; godot-dotnet and" \
      "godot cannot be combined, so remove one of them from the configuration, or remove the file"
  elif [[ -e "${LINK}" ]]; then
    fail "${LINK} exists but is neither a regular file nor a symbolic link; remove it before this feature runs"
  fi

  if [[ -L "${INSTALL_ROOT}" || (-e "${INSTALL_ROOT}" && ! -d "${INSTALL_ROOT}") ]]; then
    fail "${INSTALL_ROOT} exists but is not a directory this feature created; remove it before this feature runs"
  fi
  if [[ -d "${INSTALL_ROOT}" ]]; then
    if [[ -L "${MARKER}" || ! -f "${MARKER}" || "$(stat --format '%u' "${MARKER}")" != 0 ]]; then
      fail "${INSTALL_ROOT} exists but holds no root-owned ${MARKER_NAME}, so this feature did not create it;" \
        "remove it before this feature runs"
    fi
  fi
}

# Installs what the image lacks of curl, unzip, and ca-certificates, which the install needs, and of the font
# configuration library, which the editor loads at start, then empties apt's package lists.
install_prerequisites() {
  local missing=()
  local command
  local status
  local linker_cache
  for command in curl unzip; do
    if ! command -v "${command}" >/dev/null 2>&1; then missing+=("${command}"); fi
  done
  # Known failure mode: dpkg-query exits 1 for a package dpkg has no record of. Any failed query counts as not
  # installed.
  if ! status="$(dpkg-query --show --showformat '${Status}' ca-certificates 2>/dev/null)"; then status=""; fi
  if [[ "${status}" != *'install ok installed'* ]]; then missing+=(ca-certificates); fi
  # The library is looked up the way the editor loads it, through the dynamic linker's cache, whichever package
  # provides it.
  linker_cache="$(ldconfig --print-cache)"
  if [[ ! "${linker_cache}" =~ (^|[[:space:]])libfontconfig\.so\.1[[:space:]] ]]; then missing+=(libfontconfig1); fi
  if (( ${#missing[@]} == 0 )); then return 0; fi

  log "installing missing prerequisites with apt-get: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update \
    || fail "apt-get update failed; check the image's package repositories and network access"
  DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "${missing[@]}" \
    || fail "apt-get install failed; check the image's package repositories and network access"
  rm --recursive --force "${APT_LISTS_DIR:?}"/*
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

# Sets ${installed} to "true" when both paths belong to this feature and ${LINK} already reports ${version} as an
# official stable .NET build. An installation that exits non-zero or prints anything else is replaced.
check_installed() {
  local output
  [[ -L "${LINK}" && -d "${INSTALL_ROOT}" && -f "${LINK}" ]] || return 0
  if ! output="$(run_isolated "${LINK}" --version 2>/dev/null)"; then return 0; fi
  if reports_version "${output}"; then
    log "Godot ${version} (.NET) is already installed at ${LINK}; leaving it unchanged"
    installed="true"
  fi
}

# Downloads the release's checksum list and then its .NET archive into ${work}, logging each final URL without its
# query string (GitHub's asset host signs the URL with a short-lived token) so a host change shows in the build log.
# Fails unless the list holds exactly one entry for the archive and the archive's SHA-512 digest equals that entry.
# Upstream signs nothing, so the list relies on TLS alone (openspec/specs/godot-dotnet/spec.md, "Godot .NET release
# metadata trust").
download_and_verify() {
  local url="${RELEASES}/download/${tag}"
  local final
  local entries
  archive="Godot_v${tag}_mono_linux_${arch}.zip"
  top="Godot_v${tag}_mono_linux_${arch}"
  executable="Godot_v${tag}_mono_linux.${arch}"

  # The list is fetched first: upstream uploads it last, so a build while a release is still uploading fails here.
  final="$(fetch --location --output "${work}/${CHECKSUMS}" --write-out '%{url_effective}' "${url}/${CHECKSUMS}")" \
    || fail "cannot download ${url}/${CHECKSUMS}; check that release ${tag} exists and has finished uploading," \
      "and that github.com is reachable"
  log "downloaded ${url}/${CHECKSUMS} to ${work}/${CHECKSUMS} (final URL: ${final%%\?*})"
  awk -v name="${archive}" 'NF == 2 && $2 == name' "${work}/${CHECKSUMS}" >"${work}/archive.sha512"
  entries="$(awk 'END { print NR }' "${work}/archive.sha512")"
  # No entry means the release publishes no .NET archive for this architecture; several mean a checksum list that
  # cannot be trusted to name the archive.
  [[ "${entries}" != 0 ]] \
    || fail "verification failed: ${CHECKSUMS} of release ${tag} holds no entry for ${archive}," \
      "so the release has no .NET archive for linux ${arch}; set version to a release that has one"
  [[ "${entries}" == 1 ]] \
    || fail "verification failed: ${CHECKSUMS} of release ${tag} holds ${entries} entries for ${archive}," \
      "expected exactly one; retry the build, and set version to another release if it persists"

  final="$(fetch --location --output "${work}/${archive}" --write-out '%{url_effective}' "${url}/${archive}")" \
    || fail "cannot download ${url}/${archive}; check that release ${tag} has a .NET archive for linux ${arch}"
  log "downloaded ${url}/${archive} to ${work}/${archive} (final URL: ${final%%\?*})"
  (cd "${work}" && sha512sum --check --quiet archive.sha512) \
    || fail "verification failed: ${archive} does not match its entry in ${CHECKSUMS} of release ${tag};" \
      "retry the build, and set version to another release if it persists"
}

# Fails unless every entry of the archive lies under ${top}/, which holds exactly the executable and the directory
# GodotSharp/, with no symbolic link, absolute path, or ".." component; then extracts it into ${work}/extract.
extract_archive() {
  local reason="${archive} does not have the layout of a Godot .NET release"
  local listing
  local names=()
  local name
  local rest
  local has_executable="false"
  local has_godotsharp="false"
  listing="$(unzip -Z "${work}/${archive}")" \
    || fail "cannot list the entries of ${archive}; set version to another release"
  # zipinfo starts each entry's line with its Unix mode; "l" marks a symbolic link.
  if [[ "${listing}" =~ (^|$'\n')l ]]; then
    fail "${reason}: it holds a symbolic link; set version to another release"
  fi
  readarray -t names < <(unzip -Z1 "${work}/${archive}")
  for name in "${names[@]}"; do
    if [[ "${name}" == /* || "/${name}/" == */../* ]]; then
      fail "${reason}: entry \"${name}\" is an absolute path or has a \"..\" component; set version to another release"
    fi
    [[ "${name}" == "${top}/"* ]] \
      || fail "${reason}: entry \"${name}\" lies outside ${top}/; set version to another release"
    rest="${name#"${top}/"}"
    case "${rest}" in
      "") ;;
      "${executable}") has_executable="true" ;;
      GodotSharp/*) has_godotsharp="true" ;;
      *)
        fail "${reason}: ${top}/ holds \"${rest}\" besides ${executable} and GodotSharp/;" \
          "set version to another release"
        ;;
    esac
  done
  [[ "${has_executable}" == true ]] \
    || fail "${reason}: ${top}/ holds no ${executable}; set version to another release"
  [[ "${has_godotsharp}" == true ]] \
    || fail "${reason}: ${top}/ holds no GodotSharp/ directory; set version to another release"

  mkdir "${work}/extract"
  unzip -q "${work}/${archive}" -d "${work}/extract" \
    || fail "cannot extract ${archive}; set version to another release"
  if [[ ! -f "${work}/extract/${top}/${executable}" || -L "${work}/extract/${top}/${executable}" ]]; then
    fail "${reason}: ${executable} is not a regular file; set version to another release"
  fi
  if [[ ! -d "${work}/extract/${top}/GodotSharp" || -L "${work}/extract/${top}/GodotSharp" ]]; then
    fail "${reason}: GodotSharp is not a directory; set version to another release"
  fi
  # The listing marks a link by its Unix mode, but an entry recorded on another host system can carry a link that the
  # listing does not show, so the extracted tree is checked as well: it holds only regular files and directories.
  [[ -z "$(find "${work}/extract" ! -type f ! -type d -print -quit)" ]] \
    || fail "${reason}: it holds a symbolic link or a special file; set version to another release"
}

# Writes the marker, owned by root and readable by everyone, naming the tag that is being or was installed.
write_marker() {
  printf '%s\n' "${tag}" >"${MARKER}"
  chown root:root "${MARKER}"
  chmod 0644 "${MARKER}"
}

# Moves the extracted executable, renamed to godot, and GodotSharp/ into a new release directory under ${INSTALL_ROOT},
# owned by root and writable by no one else, and checks that the executable runs and reports ${version}.
stage_release() {
  local output
  if [[ ! -d "${INSTALL_ROOT}" ]]; then
    log "creating ${INSTALL_ROOT}"
    mkdir --mode 0755 "${INSTALL_ROOT}"
    created_root="true"
    write_marker
  fi
  # A new directory in this image layer: a release directory of an earlier layer is never renamed or reused.
  staged="$(mktemp --directory "${INSTALL_ROOT}/${tag}.XXXXXX")"
  chmod 0755 "${staged}"
  mv "${work}/extract/${top}/${executable}" "${staged}/godot"
  mv "${work}/extract/${top}/GodotSharp" "${staged}/GodotSharp"
  # The archive records its own owner and modes; the installation sets them, whatever the archive holds.
  chown --recursive root:root "${staged}"
  find "${staged}" -type d -exec chmod 0755 {} +
  find "${staged}" -type f -exec chmod 0644 {} +
  chmod 0755 "${staged}/godot"
  if ! output="$(run_isolated "${staged}/godot" --version 2>"${work}/version.stderr")" \
    || ! reports_version "${output}"; then
    cat "${work}/version.stderr" >&2
    fail "the version check failed: ${executable} from ${archive} printed \"${output}\" instead of" \
      "${version}.stable.mono.official.<hash>; check that the image's C library is recent enough for this release" \
      "(glibc 2.28 for 4.2 to 4.7), or set version to another release"
  fi
  log "staged Godot ${version} (.NET) from ${archive} in ${staged}"
}

# Points ${LINK} at the staged release in one rename, then rewrites the marker and removes every other entry of
# ${INSTALL_ROOT}, such as the release the link pointed into before.
switch_release() {
  local release="${staged}"
  local name
  name="$(mktemp --dry-run "${LINK_TEMPLATE}")"
  ln --symbolic "${release}/godot" "${name}"
  temp_link="${name}"
  mv --no-target-directory "${temp_link}" "${LINK}"
  temp_link=""
  staged=""
  created_root="false"
  log "linked ${LINK} to ${release}/godot"
  write_marker
  log "removing the entries of ${INSTALL_ROOT} other than the marker and ${release}"
  find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 ! -name "${MARKER_NAME}" ! -path "${release}" \
    -exec rm --recursive --force -- {} +
}

main() {
  validate_options
  detect_platform
  readonly VERSION

  trap cleanup EXIT
  check_paths
  install_prerequisites
  work="$(mktemp --directory "${WORK_TEMPLATE}")"
  mkdir --mode 0700 "${work}/home"
  if [[ "${VERSION}" == latest ]]; then resolve_latest; fi
  check_installed
  if [[ "${installed}" == false ]]; then
    download_and_verify
    extract_archive
    stage_release
    switch_release
    log "installed Godot ${version} (.NET) from ${archive}: ${LINK} -> ${INSTALL_ROOT}"
  fi
}

main "$@"
