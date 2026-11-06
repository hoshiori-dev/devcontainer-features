#!/usr/bin/env bash
# Installs the official Blender release build from download.blender.org, verified against the release's SHA-256
# checksum file, under /opt/blender, and links its executable to /usr/local/bin/blender. Runs as root at image build
# time; the option `version` arrives as VERSION.
set -euo pipefail

readonly RELEASE_URL="https://download.blender.org/release/"
readonly TARGET="/opt/blender"
readonly COMMAND="/usr/local/bin/blender"
readonly MARKER=".devcontainer-feature-blender"
readonly STAGING="/opt/.blender-feature.XXXXXX"
readonly APT_LISTS="/var/lib/apt/lists"
readonly FLOOR_MAJOR=4
readonly FLOOR_MINOR=2
# The libraries the release links or opens in background mode, and Mesa's EGL and DRI drivers for Workbench and EEVEE.
readonly APT_LIBRARIES=(libx11-6 libxrender1 libxfixes3 libxi6 libxkbcommon0 libsm6 libice6 libxext6 libgl1 libegl1
  libegl-mesa0 libgl1-mesa-dri)
readonly DNF_LIBRARIES=(libX11 libXrender libXfixes libXi libxkbcommon libSM libICE libXext libglvnd-glx libglvnd-egl
  mesa-libEGL mesa-dri-drivers)

VERSION="${VERSION-latest}"

package_manager=""
version=""
series=""
work=""
backup=""
managed=false
activated=false
committed=false

log() {
  printf 'blender: %s\n' "$*"
}

fail() {
  printf 'blender: error: %s\n' "$*" >&2
  exit 1
}

# Restores the previous tree after a failed activation and removes the staging directory on every exit.
cleanup() {
  if [[ "${activated}" == true && "${committed}" == false ]]; then
    rm --recursive --force "${TARGET}"
    if [[ -n "${backup}" ]]; then
      mv -- "${backup}" "${TARGET}"
      ln --symbolic --force --no-dereference "${TARGET}/blender" "${COMMAND}"
    else
      rm --force "${COMMAND}"
    fi
  elif [[ -n "${backup}" && ! -e "${TARGET}" ]]; then
    mv -- "${backup}" "${TARGET}"
  fi
  if [[ -n "${work}" ]]; then rm --recursive --force "${work}"; fi
}

# Runs curl over HTTPS without following redirects: a redirect from the release host leads into Blender's mirror
# network, which the feature never uses, so curl fails on it (exit status 47) without contacting the target.
fetch() {
  curl --proto '=https' --fail --silent --show-error --location --max-redirs 0 --retry 3 "$@"
}

# Succeeds when MAJOR.MINOR $1.$2 is older than the 4.2 floor.
below_floor() {
  if (($1 > FLOOR_MAJOR || ($1 == FLOOR_MAJOR && $2 >= FLOOR_MINOR))); then return 1; fi
}

validate_options() {
  local hint="use latest, a series such as 4.5, or an exact release such as 4.5.15, 4.2.0 or later"
  [[ "${VERSION}" =~ ^(latest|(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?)$ ]] \
    || fail "option version is \"${VERSION}\"; ${hint}"
  if [[ "${VERSION}" != latest ]] && below_floor "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; then
    fail "option version is \"${VERSION}\", older than 4.2.0; ${hint}"
  fi
}

# Selects apt or dnf from the distribution family. Runs before VERSION becomes readonly: /etc/os-release assigns it.
detect_platform() {
  local family
  local machine
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release; use a Debian, Ubuntu, Fedora, or Enterprise Linux image"
  # shellcheck source=/dev/null
  family="$(. /etc/os-release && printf '%s %s\n' "${ID:-}" "${ID_LIKE:-}")"
  case " ${family} " in
    *" debian "* | *" ubuntu "*) package_manager=apt ;;
    *" fedora "* | *" rhel "*) package_manager=dnf ;;
    *) fail "unsupported distribution \"${family% }\"; use a Debian, Ubuntu, Fedora, or Enterprise Linux image" ;;
  esac
  # A glibc image may carry a musl loader from the musl package; only an image without glibc is musl-based.
  if compgen -G '/lib/ld-musl-*.so*' >/dev/null && ! getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    fail "\"${family% }\" is musl-based, which is unsupported; use a glibc image"
  fi
  machine="$(uname --machine)"
  [[ "${machine}" == x86_64 ]] \
    || fail "unsupported architecture ${machine}: Blender publishes no Linux build for it; use an amd64 image"
}

# Accepts only this feature's tree and link, and finds foreign blender commands without executing them.
check_conflicts() {
  local path
  local resolved
  local remote_path
  if [[ -e "${TARGET}" || -L "${TARGET}" ]]; then
    [[ -d "${TARGET}" && ! -L "${TARGET}" && -f "${TARGET}/${MARKER}" ]] \
      || fail "${TARGET} is unmanaged; remove the existing installation first"
    [[ "$(stat --format '%u:%a' "${TARGET}/${MARKER}")" == 0:644 && "$(stat --format '%u' "${TARGET}")" == 0 ]] \
      || fail "${TARGET} has unmanaged ownership; remove the existing installation first"
    managed=true
  fi
  if [[ -e "${COMMAND}" || -L "${COMMAND}" ]]; then
    [[ "${managed}" == true && -L "${COMMAND}" && "$(readlink "${COMMAND}")" == "${TARGET}/blender" ]] \
      || fail "${COMMAND} is occupied; remove the existing installation first"
  fi
  remote_path="${PATH}"
  if [[ "${_REMOTE_USER:-root}" != root ]]; then
    # The login shell must expand its own PATH, not the installer's PATH.
    # shellcheck disable=SC2016
    remote_path="$(runuser --login "${_REMOTE_USER}" --command 'printf "%s" "$PATH"')" \
      || fail "cannot inspect the PATH of remote user ${_REMOTE_USER}; check the configured user"
  fi
  while IFS= read -r path; do
    path="${path:-.}"
    [[ -x "${path}/blender" && ! -d "${path}/blender" ]] || continue
    resolved="$(readlink --canonicalize-missing "${path}/blender")"
    [[ "${managed}" == true && "${resolved}" == "${TARGET}/blender" ]] \
      || fail "${path}/blender conflicts with this feature; remove the existing installation first"
  done < <(printf '%s:%s\n' "${PATH}" "${remote_path}" | tr ':' '\n')
}

# Installs the missing download tools and runtime libraries from the image's configured repositories.
install_packages() {
  local packages=()
  local package
  local tool
  if [[ "${package_manager}" == apt ]]; then
    for package in curl ca-certificates tar xz-utils coreutils "${APT_LIBRARIES[@]}"; do
      if ! dpkg-query --show --showformat='${Status}' "${package}" 2>/dev/null \
        | grep --quiet 'install ok installed'; then
        packages+=("${package}")
      fi
    done
    if ((${#packages[@]} > 0)); then
      log "installing ${packages[*]} from the configured apt repositories"
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || fail "cannot update package lists; check the configured repositories"
      apt-get --yes --no-install-recommends install "${packages[@]}" \
        || fail "cannot install ${packages[*]}; check the configured repositories"
      rm --recursive --force "${APT_LISTS:?}/"*
    fi
  else
    # Enterprise Linux ships curl-minimal, which provides curl but conflicts with the curl package: check commands.
    for tool in curl tar xz sha256sum; do
      if ! command -v "${tool}" >/dev/null; then
        case "${tool}" in
          sha256sum) packages+=(coreutils) ;;
          *) packages+=("${tool}") ;;
        esac
      fi
    done
    # Fedora's base image lacks runuser, which the conflict check needs to read a remote user's PATH.
    if [[ "${_REMOTE_USER:-root}" != root ]] && ! command -v runuser >/dev/null; then packages+=(util-linux); fi
    for package in ca-certificates "${DNF_LIBRARIES[@]}"; do
      if ! rpm --query "${package}" >/dev/null; then packages+=("${package}"); fi
    done
    if ((${#packages[@]} > 0)); then
      log "installing ${packages[*]} from the configured dnf repositories"
      dnf --assumeyes --setopt=install_weak_deps=False install "${packages[@]}" \
        || fail "cannot install ${packages[*]}; check the configured repositories"
      dnf clean all
    fi
  fi
}

# Prints the href targets of an autoindex listing saved in $1, one per line.
listed_names() {
  grep --only-matching --extended-regexp 'href="[^"]*"' "$1" | sed --expression 's/^href="//' --expression 's/"$//'
}

# Sets version to the highest release of series $1 whose archive and checksum file the series listing names, and
# leaves it empty when the listing names none.
resolve_in_series() {
  local listing_url="${RELEASE_URL}Blender$1/"
  local name
  local patch
  local best=-1
  local names
  log "reading the release listing ${listing_url}"
  fetch --output "${work}/listing.html" "${listing_url}" \
    || fail "cannot read the release listing ${listing_url}; check connectivity"
  # A listing without links names no release.
  names="$(listed_names "${work}/listing.html")" || names=""
  while IFS= read -r name; do
    [[ "${name}" =~ ^blender-${1//./\\.}\.(0|[1-9][0-9]*)-linux-x64\.tar\.xz$ ]] || continue
    patch="${BASH_REMATCH[1]}"
    grep --quiet --line-regexp --fixed-strings "blender-$1.${patch}.sha256" <<<"${names}" || continue
    if ((patch > best)); then best="${patch}"; fi
  done <<<"${names}"
  if ((best >= 0)); then version="$1.${best}"; fi
}

# Sets version and series to the release VERSION selects: exact releases need no listing.
resolve_release() {
  local name
  local candidate
  local candidates=()
  if [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version="${VERSION}"
  elif [[ "${VERSION}" != latest ]]; then
    resolve_in_series "${VERSION}"
    [[ -n "${version}" ]] || fail "the release listing ${RELEASE_URL}Blender${VERSION}/ names no Linux x64 release" \
      "with a checksum file; use another series or an exact release, or retry later"
  else
    log "reading the release listing ${RELEASE_URL}"
    fetch --output "${work}/index.html" "${RELEASE_URL}" \
      || fail "cannot read the release listing ${RELEASE_URL}; check connectivity"
    while IFS= read -r name; do
      [[ "${name}" =~ ^Blender((0|[1-9][0-9]*)\.(0|[1-9][0-9]*))/$ ]] || continue
      if ! below_floor "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; then candidates+=("${BASH_REMATCH[1]}"); fi
    done < <(listed_names "${work}/index.html")
    ((${#candidates[@]} > 0)) \
      || fail "the release listing ${RELEASE_URL} names no series of 4.2 or later; pin an exact release, or retry later"
    # A new series directory exists before its files are uploaded, so the newest series may hold no release yet.
    while IFS= read -r candidate; do
      resolve_in_series "${candidate}"
      if [[ -n "${version}" ]]; then break; fi
    done < <(printf '%s\n' "${candidates[@]}" | sort --version-sort --reverse)
    [[ -n "${version}" ]] || fail "the release listing ${RELEASE_URL} names no Linux x64 release of 4.2 or later" \
      "with a checksum file; pin an exact release, or retry later"
  fi
  series="${version%.*}"
  log "selected Blender ${version}"
}

# Succeeds when the first line the executable $1 prints for --version names the selected release; starts no Python.
reports_version() {
  [[ "$("$1" --version)" =~ ^Blender\ ${version//./\\.}([[:space:]]|$) ]]
}

install_release() {
  local base="${RELEASE_URL}Blender${series}/"
  local archive="blender-${version}-linux-x64.tar.xz"
  local digest=""
  local entries=0
  local hash
  local name
  local actual
  local interpreter
  log "downloading ${base}${archive} and ${base}blender-${version}.sha256 to ${work}"
  fetch --output "${work}/${archive}" "${base}${archive}" \
    || fail "cannot download ${base}${archive}; check that release ${version} exists and the connection works"
  fetch --output "${work}/checksums" "${base}blender-${version}.sha256" \
    || fail "cannot download ${base}blender-${version}.sha256; release ${version} must publish its checksum file"
  # The last entry may lack a final newline.
  while read -r hash name || [[ -n "${hash}" ]]; do
    if [[ "${name}" == "${archive}" ]]; then
      digest="${hash}"
      entries=$((entries + 1))
    fi
  done <"${work}/checksums"
  [[ "${entries}" == 1 && "${digest}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "blender-${version}.sha256 holds ${entries} entries for ${archive}, not one valid entry; retry later"
  actual="$(sha256sum "${work}/${archive}")"
  [[ "${actual%% *}" == "${digest}" ]] || fail "${archive} does not match blender-${version}.sha256; retry the download"
  log "extracting the verified ${archive} into ${work}/new"
  mkdir "${work}/new"
  tar --extract --xz --file "${work}/${archive}" --directory "${work}/new" --strip-components=1 --no-same-owner \
    || fail "cannot extract ${archive}; check free disk space"
  rm --force "${work}/${archive}"
  reports_version "${work}/new/blender" \
    || fail "Blender ${version} cannot run on this image (see the error above); it needs an x86-64-v2 CPU, glibc" \
      "2.28 or later, and its runtime libraries; pin another release or use a supported image"
  interpreter="$(compgen -G "${work}/new/${series}/python/bin/python3.[0-9]*")" \
    || fail "release ${version} has no bundled Python interpreter under ${series}/python/bin; pin another release"
  [[ "${interpreter}" =~ ^"${work}/new/${series}/python/bin/python3."[0-9]+$ ]] \
    || fail "release ${version} has no single bundled Python interpreter under ${series}/python/bin;" \
      "pin another release"
  log "precompiling the bundled Python modules of Blender ${version}"
  "${interpreter}" -I -m compileall -q -j 0 "${work}/new/${series}" \
    || fail "cannot precompile the bundled Python modules of Blender ${version}; pin another release"
  printf '%s\n' "${version}" >"${work}/new/${MARKER}"
  chown --recursive root:root "${work}/new"
  chmod --recursive go-w "${work}/new"
  chmod 0755 "${work}/new"
  chmod 0644 "${work}/new/${MARKER}"
  if [[ "${managed}" == true ]]; then
    backup="${work}/previous"
    mv -- "${TARGET}" "${backup}"
  fi
  log "activating Blender ${version} at ${TARGET} and linking ${COMMAND}"
  mv -- "${work}/new" "${TARGET}"
  activated=true
  mkdir --parents "${COMMAND%/*}"
  ln --symbolic --force --no-dereference "${TARGET}/blender" "${COMMAND}"
  reports_version "${COMMAND}" \
    || fail "the activated Blender ${version} does not report release ${version}; pin another release"
  committed=true
}

# Succeeds when the managed installation already holds the selected release and runs.
installed_healthy() {
  [[ "${managed}" == true && -L "${COMMAND}" && "$(cat "${TARGET}/${MARKER}")" == "${version}" ]] \
    && reports_version "${TARGET}/blender"
}

main() {
  # A restrictive umask inherited from the build would leave the tree, its bytecode, and /usr/local/bin unreadable.
  umask 0022
  validate_options
  detect_platform
  readonly VERSION
  install_packages
  check_conflicts
  mkdir --parents "${STAGING%/*}"
  work="$(mktemp --directory "${STAGING}")"
  trap cleanup EXIT
  resolve_release
  if installed_healthy; then
    log "Blender ${version} is already installed at ${TARGET}; skipping the download"
    return
  fi
  install_release
}

main "$@"
