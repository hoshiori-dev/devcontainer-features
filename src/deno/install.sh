#!/usr/bin/env bash
# Installs the Deno CLI from its GitHub release, verified against the release's two SHA-256 checksum files, to
# /usr/local/bin/deno, with a directory for global tools at /usr/local/share/deno, its login-shell PATH entry in
# /etc/profile.d/deno.sh, and group deno for a non-root remote user. Runs as root at image build time; the option
# `version` arrives as VERSION. Supported images already ship Bash; the feature does not install it.
set -euo pipefail

readonly BIN_DIR="/usr/local/bin"
readonly TOOLS_ROOT="/usr/local/share/deno"
readonly PROFILE_SCRIPT="/etc/profile.d/deno.sh"
readonly LATEST_URL="https://dl.deno.land/release-latest.txt"
readonly RELEASES_URL="https://github.com/denoland/deno/releases/download"

VERSION="${VERSION-latest}"

# Installation state the EXIT trap reads.
tmp=""
staged=""
manager_ran=""

# Platform, user, and release selection shared by later steps.
family=""
target=""
tools_user=""
resolved_version=""
checksum=""

log() {
  printf 'deno: %s\n' "$*"
}

fail() {
  printf 'deno: error: %s\n' "$*" >&2
  exit 1
}

# Removes downloads, the staging file, and package-manager caches on success and failure alike. It runs under set -e:
# a failing cache cleanup fails the build and replaces the exit status, which is intended, because Requirement
# "Prerequisite packages" forbids leaving the cache behind.
cleanup() {
  local status=$?
  rm --recursive --force "${tmp}"
  if [[ -n "${staged}" ]]; then rm --force "${staged}"; fi
  if [[ -n "${manager_ran}" ]]; then log "cleaning the ${manager_ran} package cache"; fi
  case "${manager_ran}" in
    apt-get)
      apt-get clean
      rm --recursive --force /var/lib/apt/lists/*
      ;;
    dnf) dnf clean all ;;
    zypper) zypper --non-interactive clean --all ;;
  esac
  return "${status}"
}

# Runs one curl request with the transport rules every request needs and prints the HTTP status code; curl's error
# message goes to ${tmp}/curl.err. HTTPS on every hop, redirects included; an HTTP error status fails the request; a
# connection that does not open in 30 s, or stalls below 1 KiB/s for 60 s, fails instead of hanging the build.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 \
    --connect-timeout 30 --speed-limit 1024 --speed-time 60 --write-out '%{http_code}' "$@" 2>"${tmp}/curl.err"
}

# Fails for a request that failed other than with 404: $1 is the URL, $2 the HTTP code, $3 curl's exit status.
fail_request() {
  local host="${1#https://}"
  host="${host%%/*}"
  fail "request to $1 failed (HTTP ${2:-none}, curl exit $3): $(<"${tmp}/curl.err"); check network access to ${host}"
}

# Fails unless the image has glibc 2.27 or newer, belongs to a supported family, and runs on amd64 or arm64, checking
# the C library first; sets family and target. Runs before VERSION becomes readonly: /etc/os-release assigns it too.
check_platform() {
  local glibc loader os_id os_like os_name word glibc_version glibc_major glibc_minor machine
  local words=()
  # An image without getconf, or one whose getconf reports no glibc, leaves glibc empty (Scenario "C library not
  # identified").
  if ! glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null)"; then
    glibc=""
  fi
  case "${glibc}" in
    "glibc "*) ;;
    *)
      for loader in /lib/ld-musl-*; do
        [[ ! -e "${loader}" ]] \
          || fail "this image uses musl, and Deno publishes glibc builds only; use a glibc-based image"
      done
      fail "the C library could not be identified, and Deno needs glibc 2.27 or newer; use an image with glibc"
      ;;
  esac

  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release; use an image of the Debian, Fedora, or openSUSE family"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  # shellcheck source=/dev/null
  os_name="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-${ID:-unknown}}")"
  # The first word of ID, then of ID_LIKE, that names a family decides it.
  read -r -a words <<<"${os_id} ${os_like}"
  for word in "${words[@]}"; do
    case "${word}" in
      debian | ubuntu) family=debian ;;
      fedora | rhel | centos) family=fedora ;;
      opensuse) family=opensuse ;;
      *) continue ;;
    esac
    break
  done
  [[ -n "${family}" ]] \
    || fail "unsupported distribution \"${os_name}\" (ID=${os_id});" \
      "use an image of the Debian, Fedora, or openSUSE family"

  glibc_version="${glibc#glibc }"
  glibc_major="${glibc_version%%.*}"
  glibc_minor="${glibc_version#*.}"
  glibc_minor="${glibc_minor%%.*}"
  case "${glibc_major}" in
    '' | *[!0-9]*) glibc_major="" ;;
  esac
  case "${glibc_minor}" in
    '' | *[!0-9]*) glibc_minor="" ;;
  esac
  [[ -n "${glibc_major}" && -n "${glibc_minor}" ]] \
    || fail "cannot read the glibc version from \"${glibc}\"; use an image with glibc 2.27 or newer"
  if [[ "${glibc_major}" -lt 2 ]] || [[ "${glibc_major}" -eq 2 && "${glibc_minor}" -lt 27 ]]; then
    fail "glibc ${glibc_version} found, and Deno needs glibc 2.27 or newer; use an image with a newer glibc"
  fi

  machine="$(uname -m)"
  case "${machine}" in
    x86_64) target=x86_64-unknown-linux-gnu ;;
    aarch64 | arm64) target=aarch64-unknown-linux-gnu ;;
    *)
      fail "unsupported architecture \"${machine}\", and Deno publishes Linux builds for amd64 (x86_64) and" \
        "arm64 (aarch64) only; use an amd64 or arm64 image"
      ;;
  esac
}

# Fails unless version is latest or MAJOR.MINOR.PATCH, before any network access; an explicitly empty value fails too.
validate_version() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or an exact release version MAJOR.MINOR.PATCH such as 2.9.7"
  fi
  readonly VERSION
}

# Decides whether the tools directories go to group deno (a non-root remote user that exists) and sets tools_user, then
# fails on a group conflict or a missing group command, all before prerequisites or downloads change the image.
check_tools_group() {
  local uid entry account _password gid members member _account_uid primary_gid _rest user_gid user_groups
  local member_list=()
  if [[ -z "${_REMOTE_USER:-}" || "${_REMOTE_USER}" == root ]]; then return; fi
  if ! uid="$(id -u -- "${_REMOTE_USER}" 2>/dev/null)"; then return; fi
  if [[ "${uid}" == 0 ]]; then return; fi
  tools_user="${_REMOTE_USER}"

  # Every getent failure counts as "no group": groupadd then fails loudly if the group exists after all.
  if entry="$(getent group deno)"; then
    IFS=: read -r account _password gid members <<<"${entry}"
    user_gid="$(id -g -- "${tools_user}")"
    [[ "${gid}" != "${user_gid}" ]] \
      || fail "group deno is the primary group of '${tools_user}';" \
        "use a separate primary group so UID/GID remapping preserves tools access"
    IFS=, read -r -a member_list <<<"${members}"
    for member in "${member_list[@]}"; do
      [[ "${member}" == "${tools_user}" ]] \
        || fail "group deno belongs to another account: ${member}; use a group reserved for this feature"
    done
    while IFS=: read -r account _password _account_uid primary_gid _rest; do
      [[ "${primary_gid}" != "${gid}" ]] \
        || fail "group deno is the primary group of another account: ${account};" \
          "use a group reserved for this feature"
    done < <(getent passwd)
  else
    command -v groupadd >/dev/null 2>&1 \
      || fail "groupadd is missing, and group deno does not exist for remote user '${tools_user}';" \
        "add groupadd to the image, or create group deno with '${tools_user}' in it"
  fi
  user_groups="$(id -nG -- "${tools_user}")"
  case " ${user_groups} " in
    *" deno "*) ;;
    *)
      command -v usermod >/dev/null 2>&1 \
        || fail "usermod is missing, and remote user '${tools_user}' is not in group deno;" \
          "add usermod to the image, or create group deno with '${tools_user}' in it"
      ;;
  esac
}

# Installs curl, a CA certificate bundle, and unzip with the family's package manager when one of them is missing.
ensure_prerequisites() {
  local bundle manager
  local ca_present=0
  local missing_packages=()
  if ! command -v curl >/dev/null 2>&1; then missing_packages+=(curl); fi
  for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem \
    /etc/ssl/cert.pem; do
    if [[ -s "${bundle}" ]]; then
      ca_present=1
      break
    fi
  done
  if ((ca_present == 0)); then
    if [[ "${family}" == opensuse ]]; then
      missing_packages+=(ca-certificates-mozilla)
    else
      missing_packages+=(ca-certificates)
    fi
  fi
  if ! command -v unzip >/dev/null 2>&1; then missing_packages+=(unzip); fi
  if ((${#missing_packages[@]} == 0)); then return; fi
  case "${family}" in
    debian) manager=apt-get ;;
    fedora) manager=dnf ;;
    opensuse) manager=zypper ;;
  esac
  command -v "${manager}" >/dev/null 2>&1 \
    || fail "missing ${missing_packages[*]}, and this family needs ${manager} to install them;" \
      "add ${missing_packages[*]} or ${manager} to the image"
  log "installing ${missing_packages[*]} with ${manager}"
  manager_ran="${manager}"
  case "${manager}" in
    apt-get)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update \
        || fail "apt-get update failed; check the image's repositories and network access"
      apt-get install --yes --no-install-recommends "${missing_packages[@]}" \
        || fail "apt-get could not install ${missing_packages[*]}; check the image's repositories and network access"
      ;;
    dnf)
      dnf install --assumeyes --setopt=install_weak_deps=False "${missing_packages[@]}" \
        || fail "dnf could not install ${missing_packages[*]}; check the image's repositories and network access"
      ;;
    zypper)
      zypper --non-interactive refresh \
        || fail "zypper refresh failed; check the image's repositories and network access"
      zypper --non-interactive --no-refresh install --no-recommends "${missing_packages[@]}" \
        || fail "zypper could not install ${missing_packages[*]}; check the image's repositories and network access"
      ;;
  esac
}

# Sets resolved_version to VERSION, or for latest to the release the latest-release pointer names.
resolve_version() {
  local code status pointer
  if [[ "${VERSION}" != latest ]]; then
    resolved_version="${VERSION}"
    return
  fi
  log "reading the latest release from ${LATEST_URL}"
  if code="$(fetch --output "${tmp}/latest" "${LATEST_URL}")"; then
    status=0
  else
    status=$?
  fi
  if ((status != 0)); then
    [[ "${code}" != 404 ]] \
      || fail "${LATEST_URL} answered 404, so \"latest\" cannot be resolved;" \
        "pin version to an exact release or retry later"
    fail_request "${LATEST_URL}" "${code}" "${status}"
  fi
  pointer="$(<"${tmp}/latest")"
  pointer="${pointer#"${pointer%%[![:space:]]*}"}"
  pointer="${pointer%"${pointer##*[![:space:]]}"}"
  if [[ ! "${pointer}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    fail "the latest-release pointer ${LATEST_URL} returned \"${pointer:0:200}\", which is not" \
      "v<MAJOR>.<MINOR>.<PATCH>, so nothing was installed; pin version to an exact release or retry later"
  fi
  resolved_version="${BASH_REMATCH[1]}"
  log "latest resolves to ${resolved_version}"
}

# Creates the tools directories and the login-shell PATH entry; for a tools user, also group deno with that user in it.
# Existing tools keep their ownership.
setup_tools_root() {
  local group=root
  local mode=0755
  local user_groups
  if [[ -n "${tools_user}" ]]; then
    # Every getent failure counts as "no group": groupadd then fails loudly if the group exists after all.
    if ! getent group deno >/dev/null; then
      log "creating group deno"
      groupadd --system deno || fail "groupadd --system deno failed; check the image's group database"
    fi
    user_groups="$(id -nG -- "${tools_user}")"
    case " ${user_groups} " in
      *" deno "*) ;;
      *)
        log "adding ${tools_user} to group deno"
        usermod --append --groups deno "${tools_user}" \
          || fail "usermod could not add ${tools_user} to group deno; check the image's account database"
        ;;
    esac
    group=deno
    mode=2775
  fi
  mkdir --parents "${TOOLS_ROOT}/bin" /etc/profile.d
  chown --no-dereference -- "root:${group}" "${TOOLS_ROOT}" "${TOOLS_ROOT}/bin"
  chmod "${mode}" "${TOOLS_ROOT}" "${TOOLS_ROOT}/bin"
  log "writing ${PROFILE_SCRIPT}"
  # Deliberate deviation from the guide's indentation and constants: the body is the exact file users' images hold, so
  # it keeps its four-space indentation and literal tools path, and the quoted delimiter leaves ${PATH} to login shells.
  cat >"${PROFILE_SCRIPT}" <<'PROFILE'
case ":${PATH}:" in
    *:/usr/local/share/deno/bin:*) ;;
    *) export PATH="${PATH}:/usr/local/share/deno/bin" ;;
esac
PROFILE
  chmod 0644 "${PROFILE_SCRIPT}"
  log "global tools go to ${TOOLS_ROOT}/bin, group ${group}, mode ${mode}"
}

# Prints the version the deno executable $1 reports: the second field of the first line of --version. Prints nothing
# when it cannot run, so an existing deno that cannot run counts as a different version and is replaced.
reported_version() {
  local out first _name reported
  out="$("$1" --version 2>/dev/null)" || return 0
  first="${out%%$'\n'*}"
  read -r _name reported _ <<<"${first}"
  printf '%s\n' "${reported:-}"
}

# Sets checksum to the lower-case hash in checksum file $1 of the release, whose single line must name file $2.
read_checksum() {
  local file="$1"
  local name="$2"
  local line
  local lines=()
  mapfile -t lines <"${tmp}/${file}"
  if ((${#lines[@]} != 1)); then
    fail "${file} must hold exactly one line but holds ${#lines[@]}, so nothing was installed; choose another version"
  fi
  line="${lines[0]%$'\r'}"
  if [[ ! "${line}" =~ ^([0-9A-Fa-f]{64})\ [\ *](.+)$ || "${BASH_REMATCH[2]}" != "${name}" ]]; then
    fail "${file} is not a SHA-256 line for ${name}, so nothing was installed; choose another version"
  fi
  checksum="${BASH_REMATCH[1],,}"
}

# Downloads the release archive of resolved_version and verifies it, and the deno it holds, against the release's two
# checksum files. The checksum files come first; when one is missing, a HEAD request on the archive tells a release
# without checksum files from an unknown version.
download_verified_release() {
  local base="${RELEASES_URL}/v${resolved_version}"
  local archive="deno-${target}.zip"
  local archive_sum="deno-${target}.zip.sha256sum"
  local exe_sum="deno-${target}.sha256sum"
  local name code status missing_list archive_expected exe_expected sum archive_actual exe_actual
  local missing_sums=()
  log "downloading ${archive_sum} and ${exe_sum} from ${base}"
  for name in "${archive_sum}" "${exe_sum}"; do
    if code="$(fetch --output "${tmp}/${name}" "${base}/${name}")"; then
      continue
    else
      status=$?
    fi
    if [[ "${code}" == 404 ]]; then
      missing_sums+=("${name}")
    else
      fail_request "${base}/${name}" "${code}" "${status}"
    fi
  done
  if ((${#missing_sums[@]} > 0)); then
    log "checking whether ${base}/${archive} exists"
    if code="$(fetch --head --output /dev/null "${base}/${archive}")"; then
      missing_list="${missing_sums[0]}${missing_sums[1]:+ and ${missing_sums[1]}}"
      fail "the Deno ${resolved_version} release lacks ${missing_list}, so nothing was installed;" \
        "choose a release that publishes both ${archive_sum} and ${exe_sum}: 2.7.14, 2.8.0, or later"
    else
      status=$?
    fi
    [[ "${code}" != 404 ]] \
      || fail "found no release archive ${archive} for Deno ${resolved_version} (unknown version, or none for this" \
        "architecture), so nothing was installed; check the version against the Deno releases on GitHub"
    fail_request "${base}/${archive}" "${code}" "${status}"
  fi

  read_checksum "${archive_sum}" "${archive}"
  archive_expected="${checksum}"
  read_checksum "${exe_sum}" deno
  exe_expected="${checksum}"

  log "downloading ${base}/${archive}"
  if code="$(fetch --output "${tmp}/${archive}" "${base}/${archive}")"; then
    status=0
  else
    status=$?
  fi
  if ((status != 0)); then
    [[ "${code}" != 404 ]] \
      || fail "${base}/${archive} answered 404 although its checksum files exist, so nothing was installed;" \
        "retry later"
    fail_request "${base}/${archive}" "${code}" "${status}"
  fi
  sum="$(sha256sum "${tmp}/${archive}")"
  archive_actual="${sum%% *}"
  if [[ "${archive_actual}" != "${archive_expected}" ]]; then
    fail "checksum mismatch for the archive ${archive}: expected ${archive_expected}, got ${archive_actual}, so" \
      "nothing was extracted or installed; rebuild, since a repeated mismatch means the file differs from the release"
  fi

  mkdir "${tmp}/extract"
  unzip -q "${tmp}/${archive}" deno -d "${tmp}/extract" \
    || fail "unzip found no file named deno in ${archive}, or failed, so nothing was installed; check the archive"
  if [[ ! -f "${tmp}/extract/deno" || -L "${tmp}/extract/deno" ]]; then
    fail "${archive} holds no regular file named deno, so nothing was installed; check the archive"
  fi
  sum="$(sha256sum "${tmp}/extract/deno")"
  exe_actual="${sum%% *}"
  if [[ "${exe_actual}" != "${exe_expected}" ]]; then
    fail "checksum mismatch for the extracted executable deno from ${archive}: expected ${exe_expected}, got" \
      "${exe_actual}, so it was not installed; rebuild, since a repeated mismatch means the file differs from the" \
      "release"
  fi
}

# Stages the verified executable in BIN_DIR, checks the version it reports, sets up the tools directories, and renames
# it over BIN_DIR/deno, so a failure before the rename leaves the previous deno.
install_release() {
  local staged_version
  mkdir --parents "${BIN_DIR}"
  staged="$(mktemp "${BIN_DIR}/.deno.XXXXXX")"
  cp "${tmp}/extract/deno" "${staged}"
  chmod 0755 "${staged}"
  staged_version="$(reported_version "${staged}")"
  if [[ "${staged_version}" != "${resolved_version}" ]]; then
    fail "the verified executable reports version \"${staged_version}\", not ${resolved_version}, so it was not" \
      "installed; choose another version"
  fi
  setup_tools_root
  mv --force --no-target-directory "${staged}" "${BIN_DIR}/deno"
  staged=""
  log "installed Deno ${resolved_version} at ${BIN_DIR}/deno"
}

main() {
  local installed_version=""
  check_platform
  validate_version
  check_tools_group

  tmp="$(mktemp --directory)"
  trap cleanup EXIT
  # INT and TERM exit with the conventional status, so the EXIT trap's cleanup also runs on an interruption.
  trap 'exit 130' INT
  trap 'exit 143' TERM

  ensure_prerequisites
  resolve_version
  if [[ -x "${BIN_DIR}/deno" ]]; then installed_version="$(reported_version "${BIN_DIR}/deno")"; fi
  if [[ "${installed_version}" == "${resolved_version}" ]]; then
    log "version ${resolved_version} is already installed at ${BIN_DIR}/deno; skipping the download"
    setup_tools_root
    return
  fi

  download_verified_release
  install_release
}

main "$@"
