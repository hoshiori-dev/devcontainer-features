#!/bin/sh
# Installs the hf-mount daemon and the selected backends (hf-mount-nfs, hf-mount-fuse) from the GitHub release of
# huggingface/hf-mount to /usr/local/bin, and the mount helpers of those backends from the image's package
# repositories. Runs as root at image build time; the option `version` arrives as VERSION, `backend` as BACKEND, and
# `installMountDependencies` as INSTALLMOUNTDEPENDENCIES.
# Upstream publishes no checksum and no signature, so the downloads rest on TLS alone: every request is HTTPS only,
# and nothing here may relax certificate checking.
# POSIX sh, although every supported image ships bash: Alpine ships none, and the install must fail there with this
# script's glibc message, not with the shell lookup error.
set -eu

readonly REPOSITORY_URL="https://github.com/huggingface/hf-mount"
readonly LATEST_URL="${REPOSITORY_URL}/releases/latest"
readonly TAG_URL_PREFIX="${REPOSITORY_URL}/releases/tag/v"
readonly BIN_DIR="/usr/local/bin"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
# The upstream binaries need glibc 2.34 or later.
readonly MIN_GLIBC_MAJOR=2
readonly MIN_GLIBC_MINOR=34

VERSION="${VERSION-latest}"
BACKEND="${BACKEND-both}"
INSTALLMOUNTDEPENDENCIES="${INSTALLMOUNTDEPENDENCIES-true}"

arch=""
package_manager=""
nfs_package=""
release=""
work_dir=""

log() {
  printf 'hf-mount: %s\n' "$*"
}

fail() {
  printf 'hf-mount: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory on every exit, success or failure.
cleanup() {
  if [ -n "${work_dir}" ]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl with the arguments every request of this feature shares: no curl configuration file (--disable must come
# first), HTTPS only, TLS 1.2 or later, and a connection timeout. It sends no credential and retries nothing.
fetch() {
  curl --disable --silent --show-error --proto '=https' --tlsv1.2 --connect-timeout 30 "$@"
}

# Succeeds when $1 is MAJOR.MINOR.PATCH: three numbers of decimal digits, separated by dots.
is_release_number() {
  case "$1" in
    *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
    *.*.*) return 0 ;;
    *) return 1 ;;
  esac
}

# Succeeds when the distribution package $1 is installed.
is_installed() {
  case "${package_manager}" in
    apt-get)
      # dpkg-query prints nothing and exits 1 for a package dpkg has no record of, which compares as not installed.
      [ "$(dpkg-query --show --showformat '${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
      ;;
    dnf) rpm --query "$1" >/dev/null 2>&1 ;;
  esac
}

# Installs the distribution packages named in "$@" from the repositories the image configures, without recommended
# or weak dependencies, and cleans the package manager's cache.
install_packages() {
  log "installing packages with ${package_manager} from the image's repositories: $*"
  case "${package_manager}" in
    apt-get)
      apt-get update \
        || fail "apt-get update failed; check the image's package repositories and network access"
      DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "$@" \
        || fail "apt-get install failed; check the image's package repositories and network access"
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    dnf)
      dnf install --assumeyes --setopt=install_weak_deps=False "$@" \
        || fail "dnf install failed; check the image's package repositories and network access"
      dnf clean all
      ;;
  esac
}

# Fails unless the script runs as root.
require_root() {
  # A short option: this runs before the glibc check, so also on Alpine, whose BusyBox id has no --user.
  require_root_uid="$(id -u)"
  [ "${require_root_uid}" = "0" ] \
    || fail "install.sh runs with user ID ${require_root_uid};" \
      "run it as root, as the dev container tooling does at image build time"
}

# Fails unless every option holds a value its spec accepts.
validate_options() {
  if [ "${VERSION}" != "latest" ] && ! is_release_number "${VERSION}"; then
    fail "option version is \"${VERSION}\";" \
      "use \"latest\" or a release number MAJOR.MINOR.PATCH such as 0.13.1, without a leading \"v\""
  fi
  case "${BACKEND}" in
    nfs | fuse | both) ;;
    *) fail "option backend is \"${BACKEND}\"; use \"nfs\", \"fuse\", or \"both\"" ;;
  esac
  case "${INSTALLMOUNTDEPENDENCIES}" in
    true | false) ;;
    *) fail "option installMountDependencies is \"${INSTALLMOUNTDEPENDENCIES}\"; use true or false" ;;
  esac
  readonly BACKEND INSTALLMOUNTDEPENDENCIES
}

# Fails unless the machine is x86_64 or aarch64, the architectures upstream publishes binaries for; sets ${arch} to
# the name the release assets carry.
check_architecture() {
  check_architecture_machine="$(uname --machine)"
  case "${check_architecture_machine}" in
    x86_64 | aarch64) arch="${check_architecture_machine}" ;;
    *)
      fail "unsupported architecture \"${check_architecture_machine}\";" \
        "use an x86_64 or aarch64 machine, since upstream publishes hf-mount for no other"
      ;;
  esac
}

# Fails unless the image's C library is glibc MIN_GLIBC_MAJOR.MIN_GLIBC_MINOR or later.
check_glibc() {
  check_glibc_required="${MIN_GLIBC_MAJOR}.${MIN_GLIBC_MINOR}"
  # Known failure mode: on a musl-based image getconf is missing or does not know GNU_LIBC_VERSION, and the probe
  # exits non-zero.
  if ! check_glibc_answer="$(getconf GNU_LIBC_VERSION 2>/dev/null)"; then check_glibc_answer=""; fi
  case "${check_glibc_answer}" in
    "glibc "[0-9]*.[0-9]*) ;;
    *)
      fail "the upstream hf-mount binaries need glibc ${check_glibc_required} or later, and this image has no glibc;" \
        "use a Debian, Ubuntu, or Fedora image, since musl-based images such as Alpine are not supported"
      ;;
  esac
  check_glibc_found="${check_glibc_answer#glibc }"
  check_glibc_major="${check_glibc_found%%.*}"
  check_glibc_minor="${check_glibc_found#*.}"
  check_glibc_minor="${check_glibc_minor%%.*}"
  if [ "${check_glibc_major}" -gt "${MIN_GLIBC_MAJOR}" ]; then return 0; fi
  if [ "${check_glibc_major}" -eq "${MIN_GLIBC_MAJOR}" ] && [ "${check_glibc_minor}" -ge "${MIN_GLIBC_MINOR}" ]; then
    return 0
  fi
  fail "the upstream hf-mount binaries need glibc ${check_glibc_required} or later," \
    "and this image has glibc ${check_glibc_found}; use an image with glibc ${check_glibc_required} or later"
}

# Fails unless the image is Debian, Ubuntu, or Fedora; sets ${package_manager} and ${nfs_package}, the package that
# provides mount.nfs there. Runs before VERSION becomes readonly: /etc/os-release assigns it too.
detect_distribution() {
  [ -r /etc/os-release ] \
    || fail "cannot read /etc/os-release, so the distribution is unknown; use a Debian, Ubuntu, or Fedora image"
  # shellcheck source=/dev/null
  detect_distribution_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${detect_distribution_id}" in
    debian | ubuntu)
      package_manager="apt-get"
      nfs_package="nfs-common"
      ;;
    fedora)
      package_manager="dnf"
      nfs_package="nfs-utils"
      ;;
    *) fail "unsupported distribution \"${detect_distribution_id}\"; use a Debian, Ubuntu, or Fedora image" ;;
  esac
}

# Installs curl and ca-certificates, which the downloads need, where the image lacks them. The missing packages are
# this function's positional parameters.
install_download_tools() {
  set --
  if ! command -v curl >/dev/null 2>&1; then set -- "$@" curl; fi
  if ! is_installed ca-certificates; then set -- "$@" ca-certificates; fi
  if [ "$#" -eq 0 ]; then return 0; fi
  install_packages "$@"
}

# Sets ${release} to the release to install: VERSION, or for "latest" the release that LATEST_URL redirects to. The
# redirect is read, not followed, and its target must be TAG_URL_PREFIX followed by a release number.
resolve_release() {
  if [ "${VERSION}" != "latest" ]; then
    release="${VERSION}"
    return 0
  fi
  if resolve_release_answer="$(
    fetch --output /dev/null --write-out '%{http_code} %{redirect_url}' "${LATEST_URL}"
  )"; then
    resolve_release_curl_status=0
  else
    resolve_release_curl_status=$?
  fi
  resolve_release_http_status="${resolve_release_answer%% *}"
  resolve_release_target="${resolve_release_answer#* }"
  if [ "${resolve_release_curl_status}" -ne 0 ]; then
    fail "cannot read ${LATEST_URL}: HTTP status ${resolve_release_http_status}," \
      "curl exit status ${resolve_release_curl_status};" \
      "check network access to github.com, or set version to a release number"
  fi
  # A target that does not start with the prefix stays whole, and a URL is no release number.
  release="${resolve_release_target#"${TAG_URL_PREFIX}"}"
  is_release_number "${release}" \
    || fail "${LATEST_URL} answered HTTP status ${resolve_release_http_status}" \
      "and the redirect target \"${resolve_release_target}\"," \
      "not a redirect to ${TAG_URL_PREFIX}<MAJOR.MINOR.PATCH>; set version to a release number"
  log "read the latest release ${release} from the redirect of ${LATEST_URL}"
}

# Downloads the binaries named in "$@" from release ${release} into a new ${work_dir}, each from its exact asset
# name, so no similarly named asset can be installed instead. Redirects are followed over HTTPS only.
download_binaries() {
  work_dir="$(mktemp --directory)"
  for download_binaries_binary in "$@"; do
    download_binaries_asset="${download_binaries_binary}-${arch}-linux"
    download_binaries_url="${REPOSITORY_URL}/releases/download/v${release}/${download_binaries_asset}"
    log "downloading ${download_binaries_url} to ${work_dir}/${download_binaries_binary}"
    if download_binaries_http_status="$(
      fetch --fail --location --proto-redir '=https' --output "${work_dir}/${download_binaries_binary}" \
        --write-out '%{http_code}' "${download_binaries_url}"
    )"; then
      download_binaries_curl_status=0
    else
      download_binaries_curl_status=$?
    fi
    if [ "${download_binaries_curl_status}" -ne 0 ] && [ "${download_binaries_http_status}" = "404" ]; then
      fail "release ${release} of huggingface/hf-mount does not exist," \
        "or it has no asset named ${download_binaries_asset}:" \
        "${download_binaries_url} answered HTTP status 404;" \
        "set version to a release that publishes this asset"
    fi
    if [ "${download_binaries_curl_status}" -ne 0 ]; then
      fail "cannot download ${download_binaries_url}: HTTP status ${download_binaries_http_status}," \
        "curl exit status ${download_binaries_curl_status};" \
        "check network access to github.com and build again"
    fi
  done
}

# Installs the packages that provide the mount helpers of the selected backends, where the image lacks them:
# ${nfs_package} for mount.nfs and fuse3 for fusermount3. The missing packages are this function's positional
# parameters.
install_mount_helpers() {
  set --
  if [ "${BACKEND}" != "fuse" ] && ! is_installed "${nfs_package}"; then set -- "$@" "${nfs_package}"; fi
  if [ "${BACKEND}" != "nfs" ] && ! is_installed fuse3; then set -- "$@" fuse3; fi
  if [ "$#" -eq 0 ]; then return 0; fi
  install_packages "$@"
}

# Installs the downloaded binaries named in "$@" to BIN_DIR, owned by root and executable by every user, replacing
# the ones already there.
install_binaries() {
  # Created only when missing: install --directory --mode would also change the mode of an existing directory.
  if [ ! -d "${BIN_DIR}" ]; then install --directory --mode 0755 "${BIN_DIR}"; fi
  for install_binaries_binary in "$@"; do
    log "installing ${install_binaries_binary} ${release} to ${BIN_DIR}/${install_binaries_binary}"
    install --owner root --group root --mode 0755 \
      "${work_dir}/${install_binaries_binary}" "${BIN_DIR}/${install_binaries_binary}"
  done
}

main() {
  require_root
  validate_options
  check_architecture
  check_glibc
  detect_distribution
  readonly VERSION

  trap cleanup EXIT
  # dash does not run the EXIT trap when a signal ends the script; exiting from the signal's trap runs it, with the
  # status a shell reports for that signal.
  trap 'exit 130' INT
  trap 'exit 143' TERM

  install_download_tools
  resolve_release
  # The daemon and the backends BACKEND selects become this function's positional parameters. Every one of them is
  # downloaded before a mount helper is installed, and the helpers are in place before a binary is installed.
  case "${BACKEND}" in
    nfs) set -- hf-mount hf-mount-nfs ;;
    fuse) set -- hf-mount hf-mount-fuse ;;
    both) set -- hf-mount hf-mount-nfs hf-mount-fuse ;;
  esac
  download_binaries "$@"
  if [ "${INSTALLMOUNTDEPENDENCIES}" = "true" ]; then install_mount_helpers; fi
  install_binaries "$@"
}

main "$@"
