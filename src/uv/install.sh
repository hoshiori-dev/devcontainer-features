#!/bin/sh
# Installs Astral's uv (uv and uvx) from the GitHub releases of astral-sh/uv, verified against the SHA-256 published
# beside the release archive, to /usr/local/bin; optionally installs Python command-line tools with it to
# /usr/local/share/uv; prepares the mount point of the per-dev-container volume at /var/lib/uv; and installs the
# volume-repair script to /usr/local/share/uv-feature and a login-shell snippet to /etc/profile.d/uv.sh. Runs as root
# at image build time; the option `version` arrives as VERSION and `toolsToInstall` as TOOLSTOINSTALL.
# POSIX sh, because Alpine ships no bash.
set -eu

readonly RELEASES_URL="https://github.com/astral-sh/uv/releases"
# The first release that checks the hashes a package index supplies (needed for toolsToInstall).
readonly MIN_TOOLS_VERSION="0.12.16"
readonly BIN_DIR="/usr/local/bin"
readonly VOLUME_DIR="/var/lib/uv"
readonly SHARE_DIR="/usr/local/share/uv"
readonly PROFILE_SNIPPET="/etc/profile.d/uv.sh"
readonly REPAIR_DIR="/usr/local/share/uv-feature"
readonly REPAIR_PATH="${REPAIR_DIR}/repair-volume"

# A package name, at most one bracketed extra, at most one version constraint, and no whitespace; with ARCHIVE_RE,
# nothing that uv could read as an option, a URL, or a path.
readonly NAME_RE='[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?'
readonly TOOL_RE="^${NAME_RE}(\\[${NAME_RE}\\])?((==|~=|!=|>=|<=|>|<|@)[A-Za-z0-9][A-Za-z0-9.*+!_-]*)?\$"
# A package name that ends in a wheel or source-archive suffix, which uv reads as a path to a local file (checked
# lower-cased, on the name without extra or constraint).
readonly ARCHIVE_RE='\.(whl|zip|tgz|tbz|txz|tar|tar\.(gz|bz2|xz|lz|lzma|zst))$'
readonly NL='
'

VERSION="${VERSION-latest}"
TOOLSTOINSTALL="${TOOLSTOINSTALL-}"

# The user the dev container tooling installs the feature for.
readonly REMOTE_USER="${_REMOTE_USER:-root}"

# The validated toolsToInstall entries, one per line; an entry never contains whitespace.
tools=""
# What trim returns.
trimmed=""
arch=""
libc=""
family=""
remote_uid=""
# The group and the mode the feature's directories get; the group starts as the remote user's primary group.
remote_group=""
dir_mode=""
# The ID of the group uv; empty while the image has none.
uv_group=""
release=""
work_dir=""

log() {
  printf 'uv: %s\n' "$*"
}

fail() {
  printf 'uv: error: %s\n' "$*" >&2
  exit 1
}

# Removes the work directory and any staged executable on every exit, success or failure.
cleanup() {
  if [ -n "${work_dir}" ]; then rm -rf "${work_dir}"; fi
  rm -f "${BIN_DIR}/.uv.new" "${BIN_DIR}/.uvx.new"
}

# Runs curl with the transport rules every request of this feature needs: HTTPS only, TLS 1.2 or later, HTTP errors
# fail, three retries.
request() {
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --retry 3 "$@"
}

# Runs request for a download: it follows redirects, over HTTPS only.
download() {
  request --proto-redir '=https' --location "$@"
}

# Whether $1 is a release as MAJOR.MINOR.PATCH, digits only.
is_release() {
  case "$1" in
    *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
    *.*.*) return 0 ;;
    *) return 1 ;;
  esac
}

# Whether $1 is a SHA-256 digest: 64 characters of 0-9 and a-f.
is_sha256() {
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 64 ]
}

# Whether $1, a single line, matches the extended regular expression $2. The toolsToInstall patterns have no exact
# glob equivalent, so they stay regular expressions. grep matches per line, so a value with a newline is refused
# first, and it reads the value from a here-document, so no pipeline's status decides the result.
matches() {
  case "$1" in
    *"${NL}"*) return 1 ;;
  esac
  grep -Eq "$2" <<EOF
$1
EOF
}

# Whether release $1 is older than release $2 (both MAJOR.MINOR.PATCH).
older_than() {
  older_than_a_major="${1%%.*}"
  older_than_a_patch="${1##*.}"
  older_than_a_minor="${1#*.}"
  older_than_a_minor="${older_than_a_minor%.*}"
  older_than_b_major="${2%%.*}"
  older_than_b_patch="${2##*.}"
  older_than_b_minor="${2#*.}"
  older_than_b_minor="${older_than_b_minor%.*}"
  if [ "${older_than_a_major}" -lt "${older_than_b_major}" ]; then return 0; fi
  if [ "${older_than_a_major}" -gt "${older_than_b_major}" ]; then return 1; fi
  if [ "${older_than_a_minor}" -lt "${older_than_b_minor}" ]; then return 0; fi
  if [ "${older_than_a_minor}" -gt "${older_than_b_minor}" ]; then return 1; fi
  [ "${older_than_a_patch}" -lt "${older_than_b_patch}" ]
}

# Sets trimmed to $1 without leading and trailing whitespace.
trim() {
  trimmed="$1"
  while :; do
    case "${trimmed}" in
      [[:space:]]*) trimmed="${trimmed#?}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "${trimmed}" in
      *[[:space:]]) trimmed="${trimmed%?}" ;;
      *) break ;;
    esac
  done
}

# Whether the group ID $1 is among the space-separated group IDs $2; false for an empty $1.
has_gid() {
  if [ -z "$1" ]; then return 1; fi
  case " $2 " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Whether the image has a CA certificate bundle where one of the supported distributions keeps it.
has_ca_bundle() {
  for has_ca_bundle_file in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
    if [ -s "${has_ca_bundle_file}" ]; then return 0; fi
  done
  return 1
}

# VERSION becomes readonly in main, after the last read of /etc/os-release, which assigns it too.
validate_version() {
  if [ "${VERSION}" != latest ] && ! is_release "${VERSION}"; then
    fail "option version is \"${VERSION}\"; use \"latest\" or a release such as ${MIN_TOOLS_VERSION}"
  fi
}

# Sets tools to the entries of TOOLSTOINSTALL: split at commas, trimmed, empty ones skipped, each one a package name
# with at most one extra and one constraint.
validate_tools() {
  validate_tools_form="a package name with at most one bracketed extra and one version constraint"
  validate_tools_operators="==, ~=, !=, >=, <=, >, <, or @ followed by a version"
  validate_tools_hint="list the package by name, without options, URLs, paths, or whitespace"
  # Each comma-separated entry becomes one positional parameter, so an entry that holds a newline stays one entry.
  # IFS and globbing are restored before any entry is validated.
  validate_tools_ifs="${IFS}"
  set -f
  IFS=,
  # The list is split into its entries on purpose.
  # shellcheck disable=SC2086
  set -- ${TOOLSTOINSTALL}
  IFS="${validate_tools_ifs}"
  set +f
  for validate_tools_raw in "$@"; do
    trim "${validate_tools_raw}"
    if [ -z "${trimmed}" ]; then continue; fi
    if ! matches "${trimmed}" "${TOOL_RE}"; then
      validate_tools_reason="toolsToInstall entry \"${trimmed}\" is not ${validate_tools_form}"
      fail "${validate_tools_reason} (${validate_tools_operators}); ${validate_tools_hint}"
    fi
    validate_tools_name="${trimmed%%[!A-Za-z0-9._-]*}"
    validate_tools_name="$(
      tr '[:upper:]' '[:lower:]' <<EOF
${validate_tools_name}
EOF
    )"
    if matches "${validate_tools_name}" "${ARCHIVE_RE}"; then
      validate_tools_reason="toolsToInstall entry \"${trimmed}\" ends in an archive or wheel suffix"
      fail "${validate_tools_reason}, which uv reads as a local path; ${validate_tools_hint}"
    fi
    tools="${tools}${trimmed}${NL}"
  done
  readonly TOOLSTOINSTALL
}

# Fails when tools are requested with a named release older than MIN_TOOLS_VERSION; resolve_release checks `latest`.
check_tools_release() {
  if [ -n "${tools}" ] && [ "${VERSION}" != latest ] && older_than "${VERSION}" "${MIN_TOOLS_VERSION}"; then
    check_tools_release_reason="toolsToInstall needs uv ${MIN_TOOLS_VERSION} or later, which checks the hashes the"
    check_tools_release_reason="${check_tools_release_reason} package index supplies, but version is ${VERSION}"
    fail "${check_tools_release_reason}; set version to ${MIN_TOOLS_VERSION} or later, or to latest"
  fi
}

# Sets arch and libc to the parts of the release archive's name that fit this image.
detect_target() {
  detect_target_machine="$(uname --machine)"
  case "${detect_target_machine}" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) fail "unsupported architecture \"${detect_target_machine}\"; use an x86_64 or aarch64 machine" ;;
  esac

  libc=gnu
  for detect_target_loader in /lib/ld-musl-*.so.1; do
    if [ -e "${detect_target_loader}" ]; then libc=musl; fi
  done
}

# Sets family to the package manager of the distribution's family. Runs before VERSION becomes readonly:
# /etc/os-release assigns it too.
detect_family() {
  detect_family_hint="use a Debian- or Ubuntu-based, RHEL- or Fedora-based, Arch Linux, Alpine, openSUSE, or"
  detect_family_hint="${detect_family_hint} SUSE image"
  [ -r /etc/os-release ] \
    || fail "cannot read /etc/os-release to detect the distribution; ${detect_family_hint}"
  # shellcheck source=/dev/null
  detect_family_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  detect_family_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  # shellcheck source=/dev/null
  detect_family_name="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-${ID:-unknown}}")"
  case "${detect_family_id}" in
    opensuse*) family=zypper ;;
  esac
  # ID and ID_LIKE are lists of words; set -f keeps a word from being read as a glob.
  set -f
  for detect_family_word in ${detect_family_id} ${detect_family_like}; do
    if [ -n "${family}" ]; then break; fi
    case "${detect_family_word}" in
      debian | ubuntu) family=apt ;;
      rhel | centos | fedora) family=dnf ;;
      arch) family=pacman ;;
      alpine) family=apk ;;
      suse | opensuse) family=zypper ;;
    esac
  done
  set +f
  if [ -z "${family}" ]; then
    detect_family_ids="ID=${detect_family_id}, ID_LIKE=${detect_family_like}"
    fail "unsupported distribution \"${detect_family_name}\" (${detect_family_ids}); ${detect_family_hint}"
  fi
}

# Fails, before any download or file change, when the remote user does not exist or cannot get write access through
# the group uv. Sets remote_uid, remote_group, and uv_group.
check_remote_user() {
  remote_uid="$(id -u "${REMOTE_USER}" 2>/dev/null)" \
    || fail "remote user \"${REMOTE_USER}\" does not exist in the image; set remoteUser to an existing user"
  remote_group="$(id -g "${REMOTE_USER}")"
  if [ "${remote_uid}" = 0 ]; then return 0; fi

  uv_group="$(awk -F: '$1 == "uv" {print $3}' /etc/group)"
  if [ -n "${uv_group}" ]; then
    [ "${uv_group}" != "${remote_group}" ] \
      || fail "group uv is the primary group of \"${REMOTE_USER}\"; give the user another primary group"
    check_remote_user_members="$(
      awk -F: -v user="${REMOTE_USER}" '$1 == "uv" {
        n = split($4, members, ",")
        for (i = 1; i <= n; i++) if (members[i] != "" && members[i] != user) printf "%s ", members[i]
      }' /etc/group
    )"
    # An account can be both a listed member and a primary-group member; it is named once.
    check_remote_user_primary="$(
      awk -F: -v gid="${uv_group}" -v user="${REMOTE_USER}" -v listed=" ${check_remote_user_members}" \
        '$4 == gid && $1 != user && index(listed, " " $1 " ") == 0 {printf "%s ", $1}' /etc/passwd
    )"
    check_remote_user_others="${check_remote_user_members}${check_remote_user_primary}"
    check_remote_user_hint="remove them from the group or use an image without it"
    [ -z "${check_remote_user_others}" ] \
      || fail "group uv has other accounts: ${check_remote_user_others% }; ${check_remote_user_hint}"
  elif ! command -v groupadd >/dev/null 2>&1 && ! command -v addgroup >/dev/null 2>&1; then
    check_remote_user_hint="use an image with groupadd or addgroup"
    fail "cannot create group uv: neither groupadd nor addgroup is available; ${check_remote_user_hint}"
  fi
  check_remote_user_gids="$(id -G "${REMOTE_USER}")"
  if ! has_gid "${uv_group}" "${check_remote_user_gids}" \
    && ! command -v usermod >/dev/null 2>&1 && ! command -v addgroup >/dev/null 2>&1; then
    check_remote_user_reason="cannot add \"${REMOTE_USER}\" to group uv: neither usermod nor addgroup is available"
    fail "${check_remote_user_reason}; use an image with usermod or addgroup"
  fi
}

# Installs curl, CA certificates, tar, and sha256sum, where the image lacks them, from the repositories the image
# already configures; runs no package manager when nothing is missing.
install_missing() {
  install_missing_packages=""
  if ! command -v curl >/dev/null 2>&1; then
    install_missing_packages="${install_missing_packages} curl"
  fi
  if ! has_ca_bundle; then
    if [ "${family}" = zypper ]; then
      install_missing_packages="${install_missing_packages} ca-certificates-mozilla"
    else
      install_missing_packages="${install_missing_packages} ca-certificates"
    fi
  fi
  if ! command -v tar >/dev/null 2>&1; then
    install_missing_packages="${install_missing_packages} tar"
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    install_missing_packages="${install_missing_packages} coreutils"
  fi
  if [ -z "${install_missing_packages}" ]; then return 0; fi

  case "${family}" in
    apt) install_missing_manager=apt-get ;;
    *) install_missing_manager="${family}" ;;
  esac
  install_missing_hint="check the image's package repositories and network access"
  install_missing_failure="${install_missing_manager} cannot install${install_missing_packages}"
  install_missing_failure="${install_missing_failure}; ${install_missing_hint}"
  log "installing missing prerequisites with ${family}:${install_missing_packages}"
  command -v "${install_missing_manager}" >/dev/null 2>&1 \
    || fail "${install_missing_manager} is not available, so ${install_missing_failure}"
  case "${family}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || fail "apt-get update failed, so ${install_missing_failure}"
      # The list of package names is split into words on purpose.
      # shellcheck disable=SC2086
      apt-get install --yes --no-install-recommends ${install_missing_packages} \
        || fail "${install_missing_failure}"
      apt-get clean
      rm -rf /var/lib/apt/lists/*
      ;;
    dnf)
      # The list of package names is split into words on purpose.
      # shellcheck disable=SC2086
      dnf install --assumeyes --setopt=install_weak_deps=False ${install_missing_packages} \
        || fail "${install_missing_failure}"
      dnf clean all
      ;;
    pacman)
      # Arch supports installing a package only together with a full system upgrade. The list of package names is
      # split into words on purpose.
      # shellcheck disable=SC2086
      pacman --sync --refresh --sysupgrade --needed --noconfirm ${install_missing_packages} \
        || fail "${install_missing_failure}"
      find /var/cache/pacman/pkg -mindepth 1 -delete
      ;;
    apk)
      # The list of package names is split into words on purpose.
      # shellcheck disable=SC2086
      apk add --no-cache ${install_missing_packages} || fail "${install_missing_failure}"
      ;;
    zypper)
      # The list of package names is split into words on purpose.
      # shellcheck disable=SC2086
      zypper --non-interactive install --no-recommends ${install_missing_packages} \
        || fail "${install_missing_failure}"
      zypper --non-interactive clean --all
      ;;
  esac
  if ! command -v curl >/dev/null 2>&1 || ! has_ca_bundle || ! command -v tar >/dev/null 2>&1 \
    || ! command -v sha256sum >/dev/null 2>&1; then
    install_missing_reason="prerequisites are still missing after installing${install_missing_packages}"
    fail "${install_missing_reason}; install curl, CA certificates, tar, and sha256sum in the image"
  fi
}

# Sets release to the release to install: VERSION, or for `latest` the release the redirect of RELEASES_URL/latest
# names.
resolve_release() {
  if [ "${VERSION}" != latest ]; then
    release="${VERSION}"
    return 0
  fi
  resolve_release_hint="check access to github.com, or pin a release"
  log "resolving the latest uv release from the redirect of ${RELEASES_URL}/latest"
  # Read the redirect without following it; the release name is its last path segment.
  resolve_release_location="$(request --output /dev/null --write-out '%{redirect_url}' "${RELEASES_URL}/latest")" \
    || fail "cannot resolve the latest uv release from ${RELEASES_URL}/latest; ${resolve_release_hint}"
  release="${resolve_release_location##*/}"
  if ! is_release "${release}"; then
    resolve_release_reason="${RELEASES_URL}/latest redirected to \"${resolve_release_location}\""
    fail "${resolve_release_reason}, which names no MAJOR.MINOR.PATCH release; ${resolve_release_hint}"
  fi
  if [ -n "${tools}" ] && older_than "${release}" "${MIN_TOOLS_VERSION}"; then
    resolve_release_reason="toolsToInstall needs uv ${MIN_TOOLS_VERSION} or later, which checks the hashes the"
    resolve_release_reason="${resolve_release_reason} package index supplies, but the latest release is ${release}"
    fail "${resolve_release_reason}; set version to ${MIN_TOOLS_VERSION} or later"
  fi
}

# Installs uv and uvx of the release to BIN_DIR unless both already report that release: downloads the archive for
# this platform, verifies it against the published SHA-256, and only then replaces the executables.
install_uv() {
  install_uv_installed=""
  if [ -x "${BIN_DIR}/uv" ] && [ -x "${BIN_DIR}/uvx" ]; then
    # A present uv or uvx that cannot report its version counts as not installed, so it is replaced.
    if ! install_uv_uv_line="$("${BIN_DIR}/uv" --version 2>/dev/null)"; then
      install_uv_uv_line=""
    fi
    if ! install_uv_uvx_line="$("${BIN_DIR}/uvx" --version 2>/dev/null)"; then
      install_uv_uvx_line=""
    fi
    # The release is the second word of "uv 0.12.16 (x86_64-unknown-linux-gnu)".
    install_uv_uv_version="${install_uv_uv_line#* }"
    install_uv_uv_version="${install_uv_uv_version%% *}"
    install_uv_uvx_version="${install_uv_uvx_line#* }"
    install_uv_uvx_version="${install_uv_uvx_version%% *}"
    if [ "${install_uv_uv_version}" = "${install_uv_uvx_version}" ]; then
      install_uv_installed="${install_uv_uv_version}"
    fi
  fi
  if [ "${install_uv_installed}" = "${release}" ]; then
    log "uv ${release} is already installed in ${BIN_DIR}; nothing to download"
    return 0
  fi

  install_uv_asset="uv-${arch}-unknown-linux-${libc}.tar.gz"
  install_uv_url="${RELEASES_URL}/download/${release}/${install_uv_asset}"
  install_uv_hint="retry, since a persistent failure is an upstream problem"
  log "downloading ${install_uv_url} and its .sha256 checksum to ${work_dir}"
  download --output "${work_dir}/${install_uv_asset}" "${install_uv_url}" \
    || fail "cannot download ${install_uv_asset} of uv ${release}; check that release ${release} is published"
  download --output "${work_dir}/${install_uv_asset}.sha256" "${install_uv_url}.sha256" \
    || fail "cannot download ${install_uv_url}.sha256, so nothing was installed; ${install_uv_hint}"
  install_uv_expected="$(cut -d ' ' -f 1 <"${work_dir}/${install_uv_asset}.sha256")"
  # The digest is upstream data: an upper-case digest names the same SHA-256, so it is lower-cased, not rejected.
  install_uv_expected="$(
    tr 'A-F' 'a-f' <<EOF
${install_uv_expected}
EOF
  )"
  is_sha256 "${install_uv_expected}" \
    || fail "the checksum file of ${install_uv_asset} holds no SHA-256, so nothing was installed; ${install_uv_hint}"
  install_uv_sum="$(sha256sum "${work_dir}/${install_uv_asset}")"
  install_uv_actual="${install_uv_sum%% *}"
  if [ "${install_uv_actual}" != "${install_uv_expected}" ]; then
    install_uv_reason="checksum mismatch for ${install_uv_asset}: expected ${install_uv_expected}"
    fail "${install_uv_reason}, got ${install_uv_actual}, so nothing was installed; ${install_uv_hint}"
  fi

  log "extracting ${install_uv_asset} in ${work_dir}"
  tar --extract --gzip --file "${work_dir}/${install_uv_asset}" --directory "${work_dir}"
  install_uv_unpacked="${work_dir}/uv-${arch}-unknown-linux-${libc}"
  if [ ! -f "${install_uv_unpacked}/uv" ] || [ ! -f "${install_uv_unpacked}/uvx" ]; then
    fail "${install_uv_asset} holds no uv and uvx, so nothing was installed"
  fi
  log "installing uv and uvx ${release} to ${BIN_DIR}"
  mkdir --parents "${BIN_DIR}"
  for install_uv_executable in uv uvx; do
    cp "${install_uv_unpacked}/${install_uv_executable}" "${BIN_DIR}/.${install_uv_executable}.new"
    chmod 0755 "${BIN_DIR}/.${install_uv_executable}.new"
  done
  mv --force "${BIN_DIR}/.uv.new" "${BIN_DIR}/uv"
  mv --force "${BIN_DIR}/.uvx.new" "${BIN_DIR}/uvx"
  install_uv_line="$("${BIN_DIR}/uv" --version)"
  log "installed ${install_uv_line}"
}

# Sets remote_group and dir_mode for the feature's directories. For a remote user other than root: the group uv,
# created when the image has none and joined by that user, with group write and setgid; supplementary membership
# survives the dev container tooling's change of the user's UID and primary GID. For root: root's group and root-only
# write.
set_up_group() {
  if [ "${remote_uid}" = 0 ]; then
    remote_group=0
    dir_mode=0755
    return 0
  fi
  if [ -z "${uv_group}" ]; then
    log "creating the system group uv"
    # Images with the shadow tools have groupadd; BusyBox images such as Alpine have only addgroup.
    if command -v groupadd >/dev/null 2>&1; then
      groupadd --system uv || fail "cannot create group uv"
    else
      addgroup --system uv || fail "cannot create group uv"
    fi
    uv_group="$(awk -F: '$1 == "uv" {print $3}' /etc/group)"
  fi
  set_up_group_gids="$(id -G "${REMOTE_USER}")"
  if ! has_gid "${uv_group}" "${set_up_group_gids}"; then
    log "adding ${REMOTE_USER} to the group uv"
    # Images with the shadow tools have usermod; BusyBox images such as Alpine have only addgroup.
    if command -v usermod >/dev/null 2>&1; then
      usermod --append --groups uv "${REMOTE_USER}" || fail "cannot add \"${REMOTE_USER}\" to group uv"
    else
      addgroup "${REMOTE_USER}" uv || fail "cannot add \"${REMOTE_USER}\" to group uv"
    fi
  fi
  remote_group="${uv_group}"
  dir_mode=2775
}

prepare_directories() {
  log "preparing ${VOLUME_DIR} and ${SHARE_DIR} with owner ${REMOTE_USER}:${remote_group} and mode ${dir_mode}"
  # Docker copies the empty mount point's owner, group, and mode into a new volume.
  mkdir --parents "${VOLUME_DIR}"
  chown "${REMOTE_USER}:${remote_group}" "${VOLUME_DIR}"
  chmod "${dir_mode}" "${VOLUME_DIR}"

  mkdir --parents "${SHARE_DIR}/tools" "${SHARE_DIR}/python" "${SHARE_DIR}/bin"
  chown "${REMOTE_USER}:${remote_group}" "${SHARE_DIR}" "${SHARE_DIR}/tools" "${SHARE_DIR}/python" "${SHARE_DIR}/bin"
  chmod "${dir_mode}" "${SHARE_DIR}" "${SHARE_DIR}/tools" "${SHARE_DIR}/python" "${SHARE_DIR}/bin"
}

# Installs repair_volume.sh, which onCreateCommand runs, outside the user-writable tool tree.
install_repair_script() {
  install_repair_script_source="$(dirname "$0")"
  log "installing the volume-repair script to ${REPAIR_PATH}"
  mkdir --parents "${REPAIR_DIR}"
  cp "${install_repair_script_source}/repair_volume.sh" "${REPAIR_PATH}"
  chown root:root "${REPAIR_DIR}" "${REPAIR_PATH}"
  chmod 0755 "${REPAIR_DIR}" "${REPAIR_PATH}"
}

write_profile_snippet() {
  log "writing ${PROFILE_SNIPPET}"
  mkdir --parents "${PROFILE_SNIPPET%/*}"
  # The body is the installed file: it keeps its bytes, its four-space indentation included.
  cat >"${PROFILE_SNIPPET}" <<'EOF'
# Written by the uv Dev Container Feature on every install; edits are overwritten.
# Keeps uv's tool executables on PATH in login shells whose profile resets PATH.
case ":${PATH}:" in
    *:/usr/local/share/uv/bin:*) ;;
    *) PATH="${PATH:+${PATH}:}/usr/local/share/uv/bin"; export PATH ;;
esac
EOF
  chown root:root "${PROFILE_SNIPPET}"
  chmod 0644 "${PROFILE_SNIPPET}"
}

# Installs each validated tool with uv tool install: interpreters in the image, not on the volume; a cache that goes
# away with this install; uv's default sources and checks, so no index, mirror, or hash setting is passed.
install_tools() {
  if [ -z "${tools}" ]; then return 0; fi
  mkdir --parents "${work_dir}/cache"
  # tools holds one entry per line; set -f keeps an entry such as cowsay>=6 from being read as a glob.
  set -f
  for install_tools_tool in ${tools}; do
    log "installing tool ${install_tools_tool}"
    UV_PYTHON_INSTALL_DIR="${SHARE_DIR}/python" UV_CACHE_DIR="${work_dir}/cache" UV_MANAGED_PYTHON=1 \
      UV_TOOL_DIR="${SHARE_DIR}/tools" UV_TOOL_BIN_DIR="${SHARE_DIR}/bin" \
      "${BIN_DIR}/uv" tool install "${install_tools_tool}" \
      || fail "uv tool install cannot install \"${install_tools_tool}\"; check the package name and constraint on PyPI"
  done
  set +f
}

# Gives the tool tree to the remote user, who manages tools at runtime with uv tool, without elevated privileges.
give_tool_tree() {
  log "giving ${SHARE_DIR} and everything in it to ${REMOTE_USER}:${remote_group}"
  chown --no-dereference --recursive "${REMOTE_USER}:${remote_group}" "${SHARE_DIR}"
  if [ "${remote_uid}" != 0 ]; then
    chmod -R g+w,o-w "${SHARE_DIR}"
  else
    chmod -R go-w "${SHARE_DIR}"
  fi
}

main() {
  validate_version
  validate_tools
  check_tools_release
  detect_target
  detect_family
  # After the last read of /etc/os-release, which assigns VERSION too.
  readonly VERSION
  check_remote_user
  install_missing
  resolve_release
  trap cleanup EXIT
  work_dir="$(mktemp --directory)"
  install_uv
  set_up_group
  prepare_directories
  install_repair_script
  write_profile_snippet
  install_tools
  give_tool_tree
  main_version="$("${BIN_DIR}/uv" --version)"
  log "done: ${main_version}"
}

main "$@"
