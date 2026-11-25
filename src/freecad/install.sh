#!/usr/bin/env bash
# Installs the official FreeCAD release build: the AppImage of a stable release of github.com/FreeCAD/FreeCAD, verified
# against the release's SHA-256 checksum file and unpacked under /opt/freecad, with the launchers
# /usr/local/bin/freecad and /usr/local/bin/freecadcmd. Runs as root at image build time; the option `version` arrives
# as VERSION.
set -euo pipefail

readonly RELEASES_API="https://api.github.com/repos/FreeCAD/FreeCAD/releases"
readonly DOWNLOAD_URL="https://github.com/FreeCAD/FreeCAD/releases/download"
readonly TARGET="/opt/freecad"
readonly COMMAND_DIR="/usr/local/bin"
readonly COMMANDS=(freecad freecadcmd)
readonly MARKER=".devcontainer-feature-freecad"
readonly STAGING="/opt/.freecad-feature.XXXXXX"
readonly APT_LISTS="/var/lib/apt/lists"
readonly FONTCONFIG_DIR="/etc/fonts"
readonly FLOOR_MAJOR=1
readonly FLOOR_MINOR=1
# A series is read from the release listing this many entries a page, for at most this many pages.
readonly LISTING_PAGE_SIZE=100
readonly LISTING_PAGES=10
# What the release build leaves to the host for its GUI: Mesa's OpenGL and EGL libraries with its DRI drivers, a
# fontconfig configuration, and one font family.
readonly APT_LIBRARIES=(libgl1-mesa-dri libglx-mesa0 libegl-mesa0 fontconfig-config fonts-dejavu-core)
readonly DNF_LIBRARIES=(mesa-dri-drivers mesa-libGL mesa-libEGL fontconfig dejavu-sans-fonts)

VERSION="${VERSION-latest}"

package_manager=""
asset_arch=""
version=""
asset=""
work=""
backup=""
managed=false
activated=false
committed=false

log() {
  printf 'freecad: %s\n' "$*"
}

fail() {
  printf 'freecad: error: %s\n' "$*" >&2
  exit 1
}

# Points /usr/local/bin/freecad and /usr/local/bin/freecadcmd at the launchers in the tree.
link_commands() {
  local name
  mkdir --parents "${COMMAND_DIR}"
  for name in "${COMMANDS[@]}"; do
    ln --symbolic --force --no-dereference "${TARGET}/bin/${name}" "${COMMAND_DIR}/${name}"
  done
}

# Restores the previous tree after a failed activation and removes the staging directory on every exit.
cleanup() {
  local name
  if [[ "${activated}" == true && "${committed}" == false ]]; then
    rm --recursive --force "${TARGET}"
    if [[ -n "${backup}" ]]; then
      mv -- "${backup}" "${TARGET}"
      link_commands
    else
      for name in "${COMMANDS[@]}"; do rm --force "${COMMAND_DIR}/${name}"; done
    fi
  elif [[ -n "${backup}" && ! -e "${TARGET}" ]]; then
    mv -- "${backup}" "${TARGET}"
  fi
  if [[ -n "${work}" ]]; then rm --recursive --force "${work}"; fi
}

# Runs curl with the transport rules every download in this feature needs: HTTPS on every hop, including GitHub's
# redirect from a release download URL to its release asset host.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Saves the GitHub API response for URL $1 to file $2.
fetch_metadata() {
  fetch --header 'Accept: application/vnd.github+json' --output "$2" "$1"
}

# Succeeds when MAJOR.MINOR $1.$2 is older than the 1.1 floor.
below_floor() {
  if (($1 > FLOOR_MAJOR || ($1 == FLOOR_MAJOR && $2 >= FLOOR_MINOR))); then return 1; fi
}

validate_options() {
  local hint="use latest, a series such as 1.1, or an exact release such as 1.1.4, 1.1.0 or later"
  [[ "${VERSION}" =~ ^(latest|(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?)$ ]] \
    || fail "option version is \"${VERSION}\"; ${hint}"
  if [[ "${VERSION}" != latest ]] && below_floor "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"; then
    fail "option version is \"${VERSION}\", older than 1.1.0; ${hint}"
  fi
}

# Selects apt or dnf from the distribution family and the asset architecture from the image. Runs before VERSION
# becomes readonly: /etc/os-release assigns it.
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
  case "${machine}" in
    x86_64 | aarch64) ;;
    *) fail "unsupported architecture ${machine}; use an amd64 or arm64 image" ;;
  esac
  # uname names the kernel's architecture; a 32-bit image on a 64-bit kernel reports the kernel's, so ask the image.
  if [[ "${package_manager}" == apt ]]; then
    machine="$(dpkg --print-architecture)"
  else
    machine="$(rpm --eval '%{_arch}')"
  fi
  case "${machine}" in
    amd64 | x86_64) asset_arch=x86_64 ;;
    arm64 | aarch64) asset_arch=aarch64 ;;
    *) fail "unsupported architecture ${machine}; use an amd64 or arm64 image" ;;
  esac
}

# Accepts only this feature's tree and links, and finds foreign freecad and freecadcmd commands without executing them.
check_conflicts() {
  local name
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
  for name in "${COMMANDS[@]}"; do
    path="${COMMAND_DIR}/${name}"
    if [[ -e "${path}" || -L "${path}" ]]; then
      [[ "${managed}" == true && -L "${path}" && "$(readlink "${path}")" == "${TARGET}/bin/${name}" ]] \
        || fail "${path} is occupied; remove the existing installation first"
    fi
  done
  remote_path="${PATH}"
  if [[ "${_REMOTE_USER:-root}" != root ]]; then
    # The login shell must expand its own PATH, not the installer's PATH.
    # shellcheck disable=SC2016
    remote_path="$(runuser --login "${_REMOTE_USER}" --command 'printf "%s" "$PATH"')" \
      || fail "cannot inspect the PATH of remote user ${_REMOTE_USER}; check the configured user"
  fi
  while IFS= read -r path; do
    path="${path:-.}"
    for name in "${COMMANDS[@]}"; do
      [[ -x "${path}/${name}" && ! -d "${path}/${name}" ]] || continue
      resolved="$(readlink --canonicalize-missing "${path}/${name}")"
      [[ "${managed}" == true && "${resolved}" == "${TARGET}/bin/${name}" ]] \
        || fail "${path}/${name} conflicts with this feature; remove the existing installation first"
    done
  done < <(printf '%s:%s\n' "${PATH}" "${remote_path}" | tr ':' '\n')
}

# Installs the missing download tools and the libraries and font the GUI needs from the image's configured
# repositories.
install_packages() {
  local packages=()
  local package
  local tool
  if [[ "${package_manager}" == apt ]]; then
    for package in curl ca-certificates jq coreutils "${APT_LIBRARIES[@]}"; do
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
    for tool in curl jq sha256sum; do
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

# Sets version to the numerically highest stable release of series $1 in the release listing, and leaves it empty
# when the listing holds none.
resolve_in_series() {
  local page
  local url
  local entries
  local tag
  local best=-1
  for ((page = 1; page <= LISTING_PAGES; page++)); do
    url="${RELEASES_API}?per_page=${LISTING_PAGE_SIZE}&page=${page}"
    log "reading the release listing ${url}"
    fetch_metadata "${url}" "${work}/listing.json" \
      || fail "cannot read the release listing ${url}; check connectivity, and retry later if GitHub's rate limit" \
        "for unauthenticated requests was reached"
    entries="$(jq 'length' "${work}/listing.json")" \
      || fail "the release listing ${url} is not a JSON list; retry later"
    while IFS= read -r tag; do
      [[ "${tag}" =~ ^${1//./\\.}\.(0|[1-9][0-9]*)$ ]] || continue
      if ((BASH_REMATCH[1] > best)); then best="${BASH_REMATCH[1]}"; fi
    done < <(jq --raw-output '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
      "${work}/listing.json")
    if ((entries < LISTING_PAGE_SIZE)); then
      if ((best >= 0)); then version="$1.${best}"; fi
      return
    fi
  done
  fail "the release listing ${RELEASES_API} has more than ${LISTING_PAGES} pages of ${LISTING_PAGE_SIZE} releases;" \
    "pin an exact release"
}

# Sets version to the release VERSION selects and saves that release's metadata to ${work}/release.json. Whichever
# way the release was selected, it must be a stable release whose tag is the plain version, 1.1.0 or later.
resolve_release() {
  local url
  local tag
  local stable
  if [[ "${VERSION}" == latest ]]; then
    url="${RELEASES_API}/latest"
  else
    if [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      version="${VERSION}"
    else
      resolve_in_series "${VERSION}"
      [[ -n "${version}" ]] \
        || fail "the release listing ${RELEASES_API} holds no stable release of the series ${VERSION};" \
          "use another series or an exact release"
    fi
    url="${RELEASES_API}/tags/${version}"
  fi
  log "reading the release metadata ${url}"
  fetch_metadata "${url}" "${work}/release.json" \
    || fail "cannot read the release metadata ${url}; check that the release exists and the connection works," \
      "and retry later if GitHub's rate limit for unauthenticated requests was reached"
  tag="$(jq --raw-output '.tag_name | strings' "${work}/release.json")" \
    || fail "the release metadata ${url} is not a JSON object; retry later"
  [[ "${tag}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || fail "${url} names the release \"${tag}\", whose tag is not a plain version; pin an exact release"
  if below_floor "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; then
    fail "${url} names the release ${tag}, older than 1.1.0; pin an exact release"
  fi
  stable="$(jq '.draft == false and .prerelease == false' "${work}/release.json")"
  [[ "${stable}" == true ]] \
    || fail "${url} names the release ${tag}, which is a draft or a pre-release; pin a stable release"
  if [[ -n "${version}" && "${tag}" != "${version}" ]]; then
    fail "${url} names the release ${tag}, not ${version}; retry later"
  fi
  version="${tag}"
  log "selected FreeCAD ${version}"
}

# Sets asset to the single AppImage of the selected release for this architecture, whose checksum file the release
# must hold too. The Python version in the name is upstream's to change, so it is matched, not fixed.
select_asset() {
  local name
  local names
  local matches=()
  names="$(jq --raw-output '.assets[].name' "${work}/release.json")" \
    || fail "the metadata of release ${version} lists no assets; retry later"
  while IFS= read -r name; do
    if [[ "${name}" =~ ^FreeCAD_${version//./\\.}-Linux-${asset_arch}(-py[0-9]+)?\.AppImage$ ]]; then
      matches+=("${name}")
    fi
  done <<<"${names}"
  ((${#matches[@]} == 1)) \
    || fail "release ${version} holds ${#matches[@]} AppImages for ${asset_arch}, not one; pin another release"
  asset="${matches[0]}"
  grep --quiet --line-regexp --fixed-strings "${asset}-SHA256.txt" <<<"${names}" \
    || fail "release ${version} holds no checksum file ${asset}-SHA256.txt; pin another release"
}

# Succeeds when the freecadcmd at $1 reports the selected release. FreeCAD creates its per-user directories on every
# start, so the check runs with a home inside the staging directory and leaves root's home alone.
reports_version() {
  local output
  mkdir --parents "${work}/home"
  output="$(env --unset=XDG_CONFIG_HOME --unset=XDG_DATA_HOME --unset=XDG_CACHE_HOME HOME="${work}/home" \
    "$1" --version)" || return
  grep --quiet --extended-regexp "^FreeCAD ${version//./\\.}( |\$)" <<<"${output}"
}

# Writes the launcher for the program $1 into ${work}/new/bin. It sets the variables upstream's AppRun sets for
# fonts, TLS certificates, and the Qt platform, but only where the caller left them unset, and no other variable.
write_launcher() {
  cat >"${work}/new/bin/$1" <<LAUNCHER
#!/bin/sh
# Starts FreeCAD's $1 from the release unpacked under ${TARGET}, installed by the freecad dev container feature.
# Each variable below is set only when the caller left it unset.
if [ -z "\${FONTCONFIG_FILE+set}" ]; then export FONTCONFIG_FILE="${FONTCONFIG_DIR}/fonts.conf"; fi
if [ -z "\${FONTCONFIG_PATH+set}" ]; then export FONTCONFIG_PATH="${FONTCONFIG_DIR}"; fi
if [ -z "\${SSL_CERT_FILE+set}" ]; then export SSL_CERT_FILE="${TARGET}/usr/ssl/cacert.pem"; fi
if [ -z "\${GIT_SSL_CAINFO+set}" ]; then export GIT_SSL_CAINFO="${TARGET}/usr/ssl/cacert.pem"; fi
if [ -z "\${QT_QPA_PLATFORM+set}" ]; then export QT_QPA_PLATFORM=xcb; fi
exec "${TARGET}/usr/bin/$1" "\$@"
LAUNCHER
  chmod 0755 "${work}/new/bin/$1"
}

install_release() {
  local base="${DOWNLOAD_URL}/${version}"
  local digest=""
  local entries=0
  local hash
  local name
  local actual
  log "downloading ${base}/${asset} and ${base}/${asset}-SHA256.txt to ${work}"
  fetch --output "${work}/${asset}" "${base}/${asset}" \
    || fail "cannot download ${base}/${asset}; check the connection and free disk space"
  fetch --output "${work}/checksums" "${base}/${asset}-SHA256.txt" \
    || fail "cannot download ${base}/${asset}-SHA256.txt; release ${version} must publish its checksum file"
  # The last entry may lack a final newline; sha256sum marks a binary-mode entry with a leading asterisk.
  while read -r hash name || [[ -n "${hash}" ]]; do
    if [[ "${name#\*}" == "${asset}" ]]; then
      digest="${hash}"
      entries=$((entries + 1))
    fi
  done <"${work}/checksums"
  [[ "${entries}" == 1 && "${digest}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "${asset}-SHA256.txt holds ${entries} entries for ${asset}, not one valid entry; retry later"
  actual="$(sha256sum "${work}/${asset}")"
  [[ "${actual%% *}" == "${digest}" ]] || fail "${asset} does not match ${asset}-SHA256.txt; retry the download"
  log "unpacking the verified ${asset} into ${work}/new"
  chmod 0700 "${work}/${asset}"
  mkdir "${work}/unpack"
  # The AppImage's own extraction needs no FUSE. It prints one line per file, about 100,000 of them, so its standard
  # output is dropped; errors still show.
  (cd "${work}/unpack" && "${work}/${asset}" --appimage-extract >/dev/null) \
    || fail "cannot unpack ${asset}; check free disk space"
  rm --force "${work}/${asset}"
  [[ -d "${work}/unpack/squashfs-root/usr/bin" && ! -L "${work}/unpack/squashfs-root" ]] \
    || fail "${asset} did not unpack to a tree with usr/bin; pin another release"
  mv -- "${work}/unpack/squashfs-root" "${work}/new"
  for name in "${COMMANDS[@]}"; do
    [[ -x "${work}/new/usr/bin/${name}" ]] || fail "release ${version} has no usr/bin/${name}; pin another release"
  done
  reports_version "${work}/new/usr/bin/freecadcmd" \
    || fail "FreeCAD ${version} cannot run on this image (see the error above); pin another release or use a" \
      "supported image"
  [[ -x "${work}/new/usr/bin/python" ]] \
    || fail "release ${version} has no bundled Python interpreter at usr/bin/python; pin another release"
  "${work}/new/usr/bin/python" -I -c 'import compileall' \
    || fail "the bundled Python interpreter of FreeCAD ${version} cannot run; pin another release"
  log "precompiling the bundled Python modules of FreeCAD ${version}"
  # A few bundled sources do not compile, which makes compileall exit 1; they stay uncompiled, as upstream ships them.
  "${work}/new/usr/bin/python" -I -W ignore -m compileall -qq -j 0 -s "${work}/new" -p "${TARGET}" "${work}/new/usr" \
    || log "some bundled Python sources do not compile and stay as upstream ships them"
  mkdir "${work}/new/bin"
  for name in "${COMMANDS[@]}"; do write_launcher "${name}"; done
  printf '%s\n' "${version}" >"${work}/new/${MARKER}"
  # The unpacked files keep the ownership and modes of upstream's build, some of them group-writable.
  chown --recursive --no-dereference root:root "${work}/new"
  chmod --recursive a+rX,go-w "${work}/new"
  chmod 0755 "${work}/new"
  chmod 0644 "${work}/new/${MARKER}"
  if [[ "${managed}" == true ]]; then
    backup="${work}/previous"
    mv -- "${TARGET}" "${backup}"
  fi
  log "activating FreeCAD ${version} at ${TARGET} and linking ${COMMAND_DIR}/freecad and ${COMMAND_DIR}/freecadcmd"
  mv -- "${work}/new" "${TARGET}"
  activated=true
  link_commands
  reports_version "${COMMAND_DIR}/freecadcmd" \
    || fail "the activated FreeCAD ${version} does not report release ${version}; pin another release"
  committed=true
}

# Succeeds when the managed installation already holds the selected release and runs.
installed_healthy() {
  local name
  [[ "${managed}" == true && "$(cat "${TARGET}/${MARKER}")" == "${version}" ]] || return
  for name in "${COMMANDS[@]}"; do
    [[ -L "${COMMAND_DIR}/${name}" && -x "${TARGET}/bin/${name}" && -x "${TARGET}/usr/bin/${name}" ]] || return
  done
  reports_version "${TARGET}/bin/freecadcmd"
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
    log "FreeCAD ${version} is already installed at ${TARGET}; skipping the download"
    return
  fi
  select_asset
  install_release
}

main "$@"
