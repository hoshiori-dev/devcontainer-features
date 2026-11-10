#!/usr/bin/env bash
# Installs elan, the Lean version manager, from the GitHub releases of leanprover/elan
# (https://github.com/leanprover/elan/releases), which upstream publishes without a checksum or signature, so the
# archive relies on TLS and is compared with the digest https://api.github.com reports when that API answers. elan
# goes to /usr/local/bin/elan, with the proxies lean, lake, leanc, leanmake, leanchecker, and leanpkg as links to it.
# Toolchains listed in preinstallToolchains are installed with that elan, through upstream's release index at
# https://release.lean-lang.org, into /usr/local/share/lean/toolchains. Prepares the mount point of the
# per-dev-container volume at /var/lib/lean, the group lean for a non-root remote user, and the container-creation
# script /usr/local/share/lean-feature/initialize with the default toolchain it sets. Installs curl, CA certificates,
# tar, gzip, git, and find from the image's own repositories when they are missing. Runs as root at image build time;
# the option elanVersion arrives as ELANVERSION, defaultToolchain as DEFAULTTOOLCHAIN, and preinstallToolchains as
# PREINSTALLTOOLCHAINS.
set -euo pipefail

readonly RELEASES_URL="https://github.com/leanprover/elan/releases"
readonly RELEASE_API_URL="https://api.github.com/repos/leanprover/elan/releases/tags"
# The first release that resolves the official origins through the release index at https://release.lean-lang.org.
readonly MIN_ELAN_VERSION="4.1.0"
readonly BIN_DIR="/usr/local/bin"
readonly ELAN_PATH="${BIN_DIR}/elan"
# The proxies elan's own installer creates (self_update.rs, TOOLS).
readonly PROXIES=(lean lake leanc leanmake leanchecker leanpkg)
readonly SHARE_DIR="/usr/local/share/lean"
readonly TOOLCHAINS_DIR="${SHARE_DIR}/toolchains"
readonly FEATURE_DIR="/usr/local/share/lean-feature"
readonly INITIALIZE_PATH="${FEATURE_DIR}/initialize"
readonly DEFAULT_TOOLCHAIN_PATH="${FEATURE_DIR}/default-toolchain"
readonly VOLUME_DIR="/var/lib/lean"
readonly GROUP="lean"
# stable, beta, nightly, v<MAJOR>.<MINOR>.<PATCH>[-rc<N>], or nightly-<YYYY>-<MM>-<DD>, optionally prefixed with an
# official origin.
readonly TOOLCHAIN_ORIGIN_RE='(leanprover/lean4|leanprover/lean4-nightly):'
readonly TOOLCHAIN_VERSION_RE='v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?'
readonly TOOLCHAIN_NIGHTLY_RE='nightly-[0-9]{4}-[0-9]{2}-[0-9]{2}'
readonly TOOLCHAIN_RELEASE_RE="stable|beta|nightly|${TOOLCHAIN_VERSION_RE}|${TOOLCHAIN_NIGHTLY_RE}"
readonly TOOLCHAIN_RE="^(${TOOLCHAIN_ORIGIN_RE})?(${TOOLCHAIN_RELEASE_RE})\$"
readonly TOOLCHAIN_FORMS="stable, beta, nightly, vMAJOR.MINOR.PATCH[-rcN], or nightly-YYYY-MM-DD, optionally prefixed \
with leanprover/lean4: or leanprover/lean4-nightly:"

ELANVERSION="${ELANVERSION-latest}"
DEFAULTTOOLCHAIN="${DEFAULTTOOLCHAIN-stable}"
PREINSTALLTOOLCHAINS="${PREINSTALLTOOLCHAINS-}"

# The user the dev container tooling installs the feature for.
readonly REMOTE_USER="${_REMOTE_USER:-root}"

# The validated entries of PREINSTALLTOOLCHAINS.
toolchains=()
arch=""
family=""
remote_uid=""
# The ID of the group lean; empty while the image has none.
lean_group=""
release=""
# The elan that installs toolchains: the staged new one, or the installed one when it is already the release.
elan_bin=""
work_dir=""
# The temporary elan home in which build-time toolchains are installed before they are renamed into TOOLCHAINS_DIR.
staging_home=""

log() {
  printf 'lean: %s\n' "$*"
}

fail() {
  printf 'lean: error: %s\n' "$*" >&2
  exit 1
}

# Removes the work directory, the staging home, and every staged file on every exit, success or failure.
cleanup() {
  local proxy
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
  if [[ -n "${staging_home}" ]]; then rm --recursive --force "${staging_home}"; fi
  rm --force "${BIN_DIR}/.elan.new" "${INITIALIZE_PATH}.new" "${DEFAULT_TOOLCHAIN_PATH}.new"
  for proxy in "${PROXIES[@]}"; do
    rm --force "${BIN_DIR}/.${proxy}.new"
  done
}

# Runs curl with the transport rules every request of this feature needs: HTTPS only, redirects included, HTTP errors
# fail, three retries.
request() {
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --retry 3 "$@"
}

# Runs request for a download: it follows redirects.
download() {
  request --location "$@"
}

# Whether release $1 is older than release $2, both MAJOR.MINOR.PATCH.
older_than() {
  local -a a b
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  if [[ $((10#${a[0]})) -ne $((10#${b[0]})) ]]; then
    [[ $((10#${a[0]})) -lt $((10#${b[0]})) ]]
    return
  fi
  if [[ $((10#${a[1]})) -ne $((10#${b[1]})) ]]; then
    [[ $((10#${a[1]})) -lt $((10#${b[1]})) ]]
    return
  fi
  [[ $((10#${a[2]})) -lt $((10#${b[2]})) ]]
}

# Whether the image has a CA certificate bundle where one of the supported distributions keeps it.
has_ca_bundle() {
  local bundle
  for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem; do
    if [[ -s "${bundle}" ]]; then return 0; fi
  done
  return 1
}

validate_options() {
  local raw entry
  if [[ "${ELANVERSION}" != "latest" ]]; then
    [[ "${ELANVERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || fail "option elanVersion is \"${ELANVERSION}\"; use \"latest\" or a release as MAJOR.MINOR.PATCH such as 4.2.4"
    if older_than "${ELANVERSION}" "${MIN_ELAN_VERSION}"; then
      fail "option elanVersion is \"${ELANVERSION}\", older than ${MIN_ELAN_VERSION}; use \"latest\" or a release" \
        "${MIN_ELAN_VERSION} or later"
    fi
  fi
  if [[ -n "${DEFAULTTOOLCHAIN}" && ! "${DEFAULTTOOLCHAIN}" =~ ${TOOLCHAIN_RE} ]]; then
    fail "option defaultToolchain is \"${DEFAULTTOOLCHAIN}\"; use ${TOOLCHAIN_FORMS}, or leave it empty"
  fi
  # Each comma-separated entry is read as one field, so an entry holding a newline stays one entry and fails below.
  readarray -d , -t raw <<<"${PREINSTALLTOOLCHAINS},"
  for entry in "${raw[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    if [[ -z "${entry}" ]]; then continue; fi
    [[ "${entry}" =~ ${TOOLCHAIN_RE} ]] \
      || fail "option preinstallToolchains has the entry \"${entry}\"; use ${TOOLCHAIN_FORMS}"
    toolchains+=("${entry}")
  done
  readonly ELANVERSION DEFAULTTOOLCHAIN PREINSTALLTOOLCHAINS toolchains
}

# Sets arch to the part of the release archive's name that fits this machine, and fails on a musl image.
detect_target() {
  local machine loader ldd_output
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) fail "unsupported architecture \"${machine}\"; use an x86_64 or aarch64 machine" ;;
  esac
  for loader in /lib/ld-musl-*.so.1; do
    if [[ -e "${loader}" ]]; then
      fail "this image uses the musl C library (${loader}), but elan and Lean toolchains need glibc; use a" \
        "glibc-based image such as Debian, Ubuntu, Fedora, or AlmaLinux"
    fi
  done
  # musl's ldd prints its name and exits non-zero for --version; glibc's names glibc. A missing ldd says nothing.
  ldd_output="$(ldd --version 2>&1 || true)"
  if [[ "${ldd_output,,}" == *musl* ]]; then
    fail "this image uses the musl C library, but elan and Lean toolchains need glibc; use a glibc-based image such" \
      "as Debian, Ubuntu, Fedora, or AlmaLinux"
  fi
}

# Sets family to the package manager of the distribution's family.
detect_family() {
  local hint id like name word
  hint="use a Debian- or Ubuntu-based, RHEL- or Fedora-based, Arch Linux, openSUSE, or SUSE image"
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release to detect the distribution; ${hint}"
  # shellcheck source=/dev/null
  id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  # shellcheck source=/dev/null
  name="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-${ID:-unknown}}")"
  case "${id}" in
    opensuse*) family=zypper ;;
  esac
  # ID and ID_LIKE are lists of words; set -f keeps a word from being read as a glob.
  set -f
  for word in ${id} ${like}; do
    if [[ -n "${family}" ]]; then break; fi
    case "${word}" in
      debian | ubuntu) family=apt ;;
      rhel | centos | fedora) family=dnf ;;
      arch) family=pacman ;;
      suse | opensuse) family=zypper ;;
    esac
  done
  set +f
  if [[ -z "${family}" ]]; then
    fail "unsupported distribution \"${name}\" (ID=${id}, ID_LIKE=${like}); ${hint}"
  fi
}

# Fails, before any download or file change, when the remote user does not exist or cannot get write access through
# the group lean. Sets remote_uid and lean_group.
check_remote_user() {
  local remote_gid members primary others gids
  remote_uid="$(id -u "${REMOTE_USER}" 2>/dev/null)" \
    || fail "remote user \"${REMOTE_USER}\" does not exist in the image; set remoteUser to an existing user"
  if [[ "${remote_uid}" == "0" ]]; then return 0; fi
  remote_gid="$(id -g "${REMOTE_USER}")"

  lean_group="$(awk -F: -v group="${GROUP}" '$1 == group {print $3}' /etc/group)"
  if [[ -n "${lean_group}" ]]; then
    [[ "${lean_group}" != "${remote_gid}" ]] \
      || fail "group ${GROUP} is the primary group of \"${REMOTE_USER}\"; give the user another primary group"
    members="$(
      awk -F: -v group="${GROUP}" -v user="${REMOTE_USER}" '$1 == group {
        n = split($4, members, ",")
        for (i = 1; i <= n; i++) if (members[i] != "" && members[i] != user) printf "%s ", members[i]
      }' /etc/group
    )"
    # An account can be both a listed member and a primary-group member; it is named once.
    primary="$(
      awk -F: -v gid="${lean_group}" -v user="${REMOTE_USER}" -v listed=" ${members}" \
        '$4 == gid && $1 != user && index(listed, " " $1 " ") == 0 {printf "%s ", $1}' /etc/passwd
    )"
    others="${members}${primary}"
    [[ -z "${others}" ]] \
      || fail "group ${GROUP} has other accounts: ${others% }; remove them from the group or use an image without it"
  elif ! command -v groupadd >/dev/null 2>&1; then
    fail "cannot create group ${GROUP}: groupadd is not available; use an image with groupadd"
  fi
  gids="$(id -G "${REMOTE_USER}")"
  if [[ -z "${lean_group}" || " ${gids} " != *" ${lean_group} "* ]] && ! command -v usermod >/dev/null 2>&1; then
    fail "cannot add \"${REMOTE_USER}\" to group ${GROUP}: usermod is not available; use an image with usermod"
  fi
}

# Fails when a path the feature replaces is something other than absent, a regular file, or a link, or when a
# directory the feature creates exists as something other than a directory.
check_targets() {
  local path
  for path in "${ELAN_PATH}" "${PROXIES[@]/#/${BIN_DIR}/}" "${DEFAULT_TOOLCHAIN_PATH}" "${INITIALIZE_PATH}"; do
    if [[ -e "${path}" && ! -L "${path}" && ! -f "${path}" ]]; then
      fail "${path} exists and is not a regular file or a link; remove it, since the feature installs that path"
    fi
  done
  for path in "${SHARE_DIR}" "${TOOLCHAINS_DIR}" "${FEATURE_DIR}" "${VOLUME_DIR}"; do
    if [[ (-e "${path}" || -L "${path}") && (-L "${path}" || ! -d "${path}") ]]; then
      fail "${path} exists and is not a directory; remove it, since the feature creates that directory"
    fi
  done
}

# Installs curl, CA certificates, tar, gzip, git, and find, where the image lacks them, from the repositories the image
# already configures; runs no package manager when nothing is missing.
install_missing() {
  local packages=() manager failure
  if ! command -v curl >/dev/null 2>&1; then packages+=(curl); fi
  if ! has_ca_bundle; then
    if [[ "${family}" == "zypper" ]]; then
      packages+=(ca-certificates-mozilla)
    else
      packages+=(ca-certificates)
    fi
  fi
  if ! command -v tar >/dev/null 2>&1; then packages+=(tar); fi
  if ! command -v gzip >/dev/null 2>&1; then packages+=(gzip); fi
  if ! command -v git >/dev/null 2>&1; then
    case "${family}" in
      dnf | zypper) packages+=(git-core) ;;
      *) packages+=(git) ;;
    esac
  fi
  if ! command -v find >/dev/null 2>&1; then packages+=(findutils); fi
  if ((${#packages[@]} == 0)); then return 0; fi

  case "${family}" in
    apt) manager=apt-get ;;
    *) manager="${family}" ;;
  esac
  failure="${manager} cannot install ${packages[*]}; check the image's package repositories and network access"
  log "installing missing prerequisites with ${manager}: ${packages[*]}"
  command -v "${manager}" >/dev/null 2>&1 \
    || fail "${manager} is not available to install ${packages[*]}; use an image that has ${manager}, or one that" \
      "already has curl, CA certificates, tar, gzip, git, and find"
  case "${family}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || fail "apt-get update failed, so ${failure}"
      apt-get install --yes --no-install-recommends "${packages[@]}" || fail "${failure}"
      apt-get clean
      rm --recursive --force /var/lib/apt/lists/*
      ;;
    dnf)
      dnf install --assumeyes --setopt=install_weak_deps=False "${packages[@]}" || fail "${failure}"
      dnf clean all
      ;;
    pacman)
      # Arch supports installing a package only together with a full system upgrade.
      pacman --sync --refresh --sysupgrade --needed --noconfirm "${packages[@]}" || fail "${failure}"
      find /var/cache/pacman/pkg /var/lib/pacman/sync -mindepth 1 -delete
      ;;
    zypper)
      zypper --non-interactive install --no-recommends "${packages[@]}" || fail "${failure}"
      zypper --non-interactive clean --all
      ;;
  esac
  if ! command -v curl >/dev/null 2>&1 || ! has_ca_bundle || ! command -v tar >/dev/null 2>&1 \
    || ! command -v gzip >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v find >/dev/null 2>&1; then
    fail "prerequisites are still missing after installing ${packages[*]}; install curl, CA certificates, tar," \
      "gzip, git, and find in the image"
  fi
}

# Sets release to the elan release to install: ELANVERSION, or for `latest` the release the redirect of
# RELEASES_URL/latest names.
resolve_release() {
  local hint location tag
  if [[ "${ELANVERSION}" != "latest" ]]; then
    release="${ELANVERSION}"
    return 0
  fi
  hint="check access to github.com, or set elanVersion to a release"
  log "resolving the latest elan release from the redirect of ${RELEASES_URL}/latest"
  # Read the redirect without following it; the tag is its last path segment.
  location="$(request --output /dev/null --write-out '%{redirect_url}' "${RELEASES_URL}/latest")" \
    || fail "cannot resolve the latest elan release from ${RELEASES_URL}/latest; ${hint}"
  tag="${location##*/}"
  if [[ "${location}" != "${RELEASES_URL}/tag/"* || ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "${RELEASES_URL}/latest redirected to \"${location}\", which names no release tag vMAJOR.MINOR.PATCH;" \
      "${hint}"
  fi
  release="${tag#v}"
}

# Prints the release the elan at $1 reports, the second word of "elan 4.2.4 (227caca13 2026-08-25)", or nothing when
# it cannot report one. elan runs with its home in the work directory, so it writes nothing to a real home.
elan_release() {
  local line
  if ! line="$(ELAN_HOME="${work_dir}/elan-home" HOME="${work_dir}" "$1" --version 2>/dev/null)"; then return 0; fi
  line="${line#elan }"
  printf '%s\n' "${line%% *}"
}

# Sets elan_bin to an elan of the release: the installed one when it already reports the release, otherwise the
# archive's elan-init, downloaded, compared with GitHub's digest when one is reported, and staged in the work directory
# under the name elan, since elan picks its mode from the name it runs as.
fetch_elan() {
  local installed asset url archive json digest actual staged
  # Only a regular file can be the feature's elan; a link elsewhere, such as into a home directory, is replaced.
  if [[ -f "${ELAN_PATH}" && ! -L "${ELAN_PATH}" && -x "${ELAN_PATH}" ]]; then
    installed="$(elan_release "${ELAN_PATH}")"
    if [[ "${installed}" == "${release}" ]]; then
      log "elan ${release} is already installed at ${ELAN_PATH}; nothing to download"
      elan_bin="${ELAN_PATH}"
      return 0
    fi
  fi

  asset="elan-${arch}-unknown-linux-gnu.tar.gz"
  url="${RELEASES_URL}/download/v${release}/${asset}"
  archive="${work_dir}/${asset}"
  json="${work_dir}/release.json"
  log "downloading ${url} to ${work_dir}"
  download --output "${archive}" "${url}" \
    || fail "cannot download ${asset} of elan ${release}; check that release ${release} is published at" \
      "${RELEASES_URL}"
  # The digest GitHub's API reports for the asset, when the API answers (it is rate-limited for anonymous callers)
  # and reports one: the digest that follows the asset's name in its object (the uploader object between them has no
  # name). The JSON is split into one member per line first, so it parses compact and indented alike. Absent, the
  # download relies on TLS alone, as the spec states.
  digest=""
  if request --location --header 'Accept: application/vnd.github+json' --output "${json}" \
    "${RELEASE_API_URL}/v${release}"; then
    digest="$(
      sed 's/[,{}]/\n/g' "${json}" | awk -F'"' -v asset="${asset}" '
        $2 == "name" { found = ($4 == asset) }
        found && $2 == "digest" { print $4; exit }'
    )"
  else
    log "GitHub's API at ${RELEASE_API_URL}/v${release} did not answer: no digest to compare"
  fi
  if [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    actual="$(sha256sum "${archive}")"
    actual="${actual%% *}"
    [[ "${actual}" == "${digest#sha256:}" ]] \
      || fail "${asset} does not match the digest GitHub reports (${digest}), so nothing was installed; retry, and" \
        "report it upstream if it persists"
    log "verified ${asset} against the digest GitHub reports"
  else
    log "GitHub reports no digest for ${asset}: the download relies on TLS alone"
  fi

  log "extracting elan-init from ${asset} in ${work_dir}"
  mkdir "${work_dir}/unpacked"
  tar --extract --gzip --no-same-owner --file "${archive}" --directory "${work_dir}/unpacked" elan-init \
    || fail "${asset} holds no elan-init, so nothing was installed; report it upstream"
  [[ -f "${work_dir}/unpacked/elan-init" && ! -L "${work_dir}/unpacked/elan-init" ]] \
    || fail "${asset} holds no regular file elan-init, so nothing was installed; report it upstream"
  mkdir "${work_dir}/bin"
  staged="${work_dir}/bin/elan"
  cp "${work_dir}/unpacked/elan-init" "${staged}"
  chmod 0755 "${staged}"
  installed="$(elan_release "${staged}")"
  [[ "${installed}" == "${release}" ]] \
    || fail "the elan in ${asset} reports \"${installed}\", not ${release}, so nothing was installed; report it" \
      "upstream"
  elan_bin="${staged}"
}

# Installs each toolchain of preinstallToolchains with elan_bin into a staging home next to SHARE_DIR, whose
# toolchains directory first links the toolchains the image already has, so elan downloads none of those again. Moves
# nothing into TOOLCHAINS_DIR; install_files does, once every toolchain is installed.
stage_toolchains() {
  local existing name
  if ((${#toolchains[@]} == 0)); then return 0; fi
  # Beside SHARE_DIR, on the same file system, so the toolchains move into place by rename, and outside it, so a failed
  # install leaves nothing there.
  staging_home="$(mktemp --directory "${SHARE_DIR%/*}/.lean-elan-home.XXXXXX")"
  mkdir "${staging_home}/toolchains" "${staging_home}/home"
  shopt -s nullglob
  for existing in "${TOOLCHAINS_DIR}"/*; do
    ln --symbolic "${existing}" "${staging_home}/toolchains/${existing##*/}"
  done
  shopt -u nullglob
  for name in "${toolchains[@]}"; do
    log "installing toolchain ${name} with elan ${release}, through https://release.lean-lang.org"
    # elan runs in an empty directory: elan 4.2 reads a name as a relative path first when that directory exists.
    if ! (cd "${staging_home}/home" \
      && ELAN_HOME="${staging_home}" HOME="${staging_home}/home" "${elan_bin}" toolchain install "${name}") 2>&1 \
      | tee "${work_dir}/toolchain.log"; then
      # elan releases before 4.2.4 exit non-zero for a toolchain that is already installed, which here means the image
      # or an earlier entry already holds it.
      if grep --quiet "is already installed" "${work_dir}/toolchain.log"; then continue; fi
      fail "elan cannot install toolchain ${name}; check that upstream publishes it for ${arch}" \
        "(https://release.lean-lang.org) and that release.lean-lang.org, releases.lean-lang.org, and github.com are" \
        "reachable"
    fi
  done
}

# Creates the group lean when the image has none and adds the remote user to it, unless the remote user is root.
set_up_group() {
  local gids
  if [[ "${remote_uid}" == "0" ]]; then return 0; fi
  if [[ -z "${lean_group}" ]]; then
    log "creating the system group ${GROUP}"
    groupadd --system "${GROUP}" || fail "cannot create group ${GROUP}"
    lean_group="$(awk -F: -v group="${GROUP}" '$1 == group {print $3}' /etc/group)"
  fi
  gids="$(id -G "${REMOTE_USER}")"
  if [[ " ${gids} " != *" ${lean_group} "* ]]; then
    log "adding ${REMOTE_USER} to the group ${GROUP}"
    usermod --append --groups "${GROUP}" "${REMOTE_USER}" || fail "cannot add \"${REMOTE_USER}\" to group ${GROUP}"
  fi
}

# Writes the files the feature installs, each staged beside its target and renamed into place: the build-time
# toolchains first, then elan, its proxies, the creation script, and the default toolchain it sets.
install_files() {
  local proxy entry name source_dir
  if [[ -n "${staging_home}" ]]; then
    mkdir --parents "${TOOLCHAINS_DIR}"
    chown root:root "${SHARE_DIR}" "${TOOLCHAINS_DIR}"
    chmod 0755 "${SHARE_DIR}" "${TOOLCHAINS_DIR}"
    shopt -s nullglob
    for entry in "${staging_home}/toolchains"/*; do
      # Links stand for toolchains the image already has; only directories elan created are new.
      if [[ -L "${entry}" || ! -d "${entry}" ]]; then continue; fi
      name="${entry##*/}"
      log "installing toolchain ${name} to ${TOOLCHAINS_DIR}/${name}"
      chown --recursive --no-dereference root:root "${entry}"
      find "${entry}" ! -type l -perm /022 -exec chmod go-w {} +
      mv --no-target-directory "${entry}" "${TOOLCHAINS_DIR}/${name}"
    done
    shopt -u nullglob
  fi

  if [[ "${elan_bin}" != "${ELAN_PATH}" ]]; then
    log "installing elan ${release} to ${ELAN_PATH}"
    cp "${elan_bin}" "${BIN_DIR}/.elan.new"
    chmod 0755 "${BIN_DIR}/.elan.new"
    mv --force --no-target-directory "${BIN_DIR}/.elan.new" "${ELAN_PATH}"
  fi
  chown root:root "${ELAN_PATH}"
  chmod 0755 "${ELAN_PATH}"
  log "linking ${PROXIES[*]} in ${BIN_DIR} to elan"
  for proxy in "${PROXIES[@]}"; do
    ln --symbolic --force elan "${BIN_DIR}/.${proxy}.new"
    mv --force --no-target-directory "${BIN_DIR}/.${proxy}.new" "${BIN_DIR}/${proxy}"
  done

  source_dir="$(dirname "$0")"
  log "installing the container-creation script to ${INITIALIZE_PATH} and the default toolchain to" \
    "${DEFAULT_TOOLCHAIN_PATH}"
  mkdir --parents "${FEATURE_DIR}"
  chown root:root "${FEATURE_DIR}"
  chmod 0755 "${FEATURE_DIR}"
  cp "${source_dir}/scripts/initialize.sh" "${INITIALIZE_PATH}.new"
  chmod 0755 "${INITIALIZE_PATH}.new"
  mv --force --no-target-directory "${INITIALIZE_PATH}.new" "${INITIALIZE_PATH}"
  printf '%s\n' "${DEFAULTTOOLCHAIN}" >"${DEFAULT_TOOLCHAIN_PATH}.new"
  chmod 0644 "${DEFAULT_TOOLCHAIN_PATH}.new"
  mv --force --no-target-directory "${DEFAULT_TOOLCHAIN_PATH}.new" "${DEFAULT_TOOLCHAIN_PATH}"
}

# Prepares the empty mount point of the volume, whose owner, group, and mode Docker copies into a new volume.
prepare_mount_point() {
  local group mode
  if [[ "${remote_uid}" == "0" ]]; then
    group=root
    mode=0755
  else
    group="${GROUP}"
    mode=2775
  fi
  log "preparing ${VOLUME_DIR} with owner ${REMOTE_USER}:${group} and mode ${mode}"
  mkdir --parents "${VOLUME_DIR}"
  chown "${REMOTE_USER}:${group}" "${VOLUME_DIR}"
  chmod "${mode}" "${VOLUME_DIR}"
}

main() {
  validate_options
  detect_target
  detect_family
  check_remote_user
  check_targets
  install_missing
  resolve_release
  trap cleanup EXIT
  work_dir="$(mktemp --directory)"
  fetch_elan
  stage_toolchains
  set_up_group
  install_files
  prepare_mount_point
  log "done: elan ${release} at ${ELAN_PATH}"
}

main "$@"
