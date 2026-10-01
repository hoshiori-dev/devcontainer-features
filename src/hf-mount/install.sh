#!/bin/sh
# Installs the hf-mount daemon and the selected backends from the upstream GitHub release into
# /usr/local/bin, with the mount helpers of those backends. Runs as root at image build time; the
# options arrive as VERSION, BACKEND, and INSTALLMOUNTDEPENDENCIES.
#
# POSIX sh, so an image without bash (Alpine) still gets the clear message. Order: every check
# first, then the download tools when missing, then every download into a temporary directory,
# then the mount helpers, then the binaries. A failing run replaces no binary. A second run
# downloads and replaces every selected binary again and removes nothing.
#
# Upstream publishes no checksum and no signature, so the downloads rest on TLS alone: every
# request is HTTPS only, and nothing here may relax certificate checking.
set -eu

# A default applies only to an unset option: an option set to the empty string is a value like any
# other and fails the checks below.
VERSION="${VERSION-latest}"
BACKEND="${BACKEND-both}"
INSTALLMOUNTDEPENDENCIES="${INSTALLMOUNTDEPENDENCIES-true}"

REPOSITORY_URL="https://github.com/huggingface/hf-mount"
LATEST_URL="${REPOSITORY_URL}/releases/latest"
TAG_URL_PREFIX="${REPOSITORY_URL}/releases/tag/v"
BIN_DIR="/usr/local/bin"
GLIBC_MAJOR=2
GLIBC_MINOR=34

fail() {
  echo "hf-mount: error: $*" >&2
  exit 1
}

# True for MAJOR.MINOR.PATCH: three dot-separated numbers, none with a leading zero.
is_release_number() {
  case "$1" in
    "" | *[!0-9.]* | *.*.*.*) return 1 ;;
    ?*.?*.?*) ;;
    *) return 1 ;;
  esac
  case ".$1" in
    *.0[0-9]*) return 1 ;;
  esac
  return 0
}

# --- Checks: nothing is installed or downloaded before all of them pass ---------------------------

[ "$(id -u)" -eq 0 ] || fail "install.sh must run as root."

if [ "${VERSION}" != "latest" ] && ! is_release_number "${VERSION}"; then
  fail "version \"${VERSION}\" is not accepted: use \"latest\" or a release number of the form" \
    "MAJOR.MINOR.PATCH, such as 0.13.1, without a leading \"v\"."
fi

case "${BACKEND}" in
  nfs) binaries="hf-mount hf-mount-nfs" ;;
  fuse) binaries="hf-mount hf-mount-fuse" ;;
  both) binaries="hf-mount hf-mount-nfs hf-mount-fuse" ;;
  *) fail "backend \"${BACKEND}\" is not accepted: use \"nfs\", \"fuse\", or \"both\"." ;;
esac

case "${INSTALLMOUNTDEPENDENCIES}" in
  true | false) ;;
  *) fail "installMountDependencies \"${INSTALLMOUNTDEPENDENCIES}\" is not accepted: use true or false." ;;
esac

machine="$(uname -m)"
case "${machine}" in
  x86_64 | aarch64) arch="${machine}" ;;
  *) fail "architecture \"${machine}\" is not supported: upstream publishes hf-mount for x86_64 and aarch64 only." ;;
esac

glibc_required="${GLIBC_MAJOR}.${GLIBC_MINOR}"
libc="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
case "${libc}" in
  "glibc "[0-9]*.[0-9]*) glibc_found="${libc#glibc }" ;;
  *)
    fail "the upstream hf-mount binaries need glibc ${glibc_required} or later, and this image provides no" \
      "glibc; musl-based images such as Alpine are not supported."
    ;;
esac
glibc_found_major="${glibc_found%%.*}"
glibc_found_minor="${glibc_found#*.}"
glibc_found_minor="${glibc_found_minor%%[!0-9]*}"
case "${glibc_found_major}:${glibc_found_minor}" in
  *[!0-9:]* | :* | *:)
    fail "cannot read the glibc version \"${glibc_found}\"; glibc ${glibc_required} or later is required."
    ;;
esac
if [ "${glibc_found_major}" -lt "${GLIBC_MAJOR}" ] \
  || { [ "${glibc_found_major}" -eq "${GLIBC_MAJOR}" ] && [ "${glibc_found_minor}" -lt "${GLIBC_MINOR}" ]; }; then
  fail "the upstream hf-mount binaries need glibc ${glibc_required} or later, and this image has glibc" \
    "${glibc_found}."
fi

distribution=""
if [ -r /etc/os-release ]; then
  # shellcheck source=/dev/null
  distribution="$(. /etc/os-release && printf '%s' "${ID:-}")"
fi
case "${distribution}" in
  debian | ubuntu)
    manager="apt"
    nfs_package="nfs-common"
    ;;
  fedora)
    manager="dnf"
    nfs_package="nfs-utils"
    ;;
  *)
    fail "distribution \"${distribution:-unknown}\" is not supported: hf-mount installs on Debian, Ubuntu, and" \
      "Fedora only."
    ;;
esac

# --- Packages -------------------------------------------------------------------------------------

package_index_fetched=false
package_manager_used=false

is_installed() {
  if [ "${manager}" = "apt" ]; then
    [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
  else
    rpm -q "$1" >/dev/null 2>&1
  fi
}

# Installs those of the named packages that are missing; runs the package manager only when one is.
install_missing() {
  missing=""
  for package in "$@"; do
    is_installed "${package}" || missing="${missing} ${package}"
  done
  [ -n "${missing}" ] || return 0
  package_manager_used=true
  echo "hf-mount: installing packages:${missing}"
  if [ "${manager}" = "apt" ]; then
    if [ "${package_index_fetched}" = false ]; then
      apt-get update
      package_index_fetched=true
    fi
    # shellcheck disable=SC2086 # the list holds fixed package names, split on purpose
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${missing}
  else
    # shellcheck disable=SC2086 # the list holds fixed package names, split on purpose
    dnf install -y --setopt=install_weak_deps=False ${missing}
  fi
}

# Runs on every exit: removes the downloads and, when a package was installed, the package caches.
work_dir=""
cleanup() {
  [ -z "${work_dir}" ] || rm -rf "${work_dir}"
  if [ "${package_manager_used}" = true ]; then
    if [ "${manager}" = "apt" ]; then
      apt-get clean || true
      rm -rf /var/lib/apt/lists/*
    else
      dnf clean all || true
    fi
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The download tools, only when the image lacks them.
download_tools=""
command -v curl >/dev/null 2>&1 || download_tools="curl"
is_installed ca-certificates || download_tools="${download_tools} ca-certificates"
# shellcheck disable=SC2086 # fixed package names, split on purpose
[ -z "${download_tools}" ] || install_missing ${download_tools}

# --- Release --------------------------------------------------------------------------------------

# Every request: HTTPS only, no curl configuration file (--disable must come first), no credential.
if [ "${VERSION}" = "latest" ]; then
  # The redirect is read, not followed: its target must be the tag page of a release number.
  curl_exit=0
  answer="$(curl --disable --silent --show-error --proto '=https' --tlsv1.2 --connect-timeout 30 \
    --output /dev/null --write-out '%{http_code} %{redirect_url}' "${LATEST_URL}")" || curl_exit=$?
  status="${answer%% *}"
  target="${answer#* }"
  if [ "${curl_exit}" -ne 0 ]; then
    fail "cannot resolve the latest release: the request to ${LATEST_URL} failed with HTTP status ${status}" \
      "(curl exit code ${curl_exit})."
  fi
  case "${status}" in
    3[0-9][0-9]) ;;
    *) fail "cannot resolve the latest release: ${LATEST_URL} answered HTTP status ${status}, not a redirect." ;;
  esac
  release="${target#"${TAG_URL_PREFIX}"}"
  if [ "${release}" = "${target}" ] || ! is_release_number "${release}"; then
    fail "cannot resolve the latest release: ${LATEST_URL} answered HTTP status ${status} with a redirect to" \
      "\"${target}\", not to ${TAG_URL_PREFIX}<MAJOR.MINOR.PATCH>."
  fi
  echo "hf-mount: the latest release is ${release}"
else
  release="${VERSION}"
fi

# --- Downloads: all of them, before anything is installed -----------------------------------------

work_dir="$(mktemp -d)"
for binary in ${binaries}; do
  # Exactly this name is requested, so no similarly named asset can be installed instead.
  asset="${binary}-${arch}-linux"
  url="${REPOSITORY_URL}/releases/download/v${release}/${asset}"
  echo "hf-mount: downloading ${url}"
  curl_exit=0
  status="$(curl --disable --silent --show-error --fail --location --proto '=https' --proto-redir '=https' \
    --tlsv1.2 --connect-timeout 30 --output "${work_dir}/${binary}" --write-out '%{http_code}' "${url}")" \
    || curl_exit=$?
  if [ "${curl_exit}" -ne 0 ]; then
    if [ "${status}" = "404" ]; then
      fail "release ${release} of huggingface/hf-mount does not exist, or it has no asset named ${asset}:" \
        "${url} answered HTTP status 404."
    fi
    fail "the download of ${url} failed with HTTP status ${status} (curl exit code ${curl_exit})."
  fi
  [ -s "${work_dir}/${binary}" ] || fail "the download of ${url} is empty (HTTP status ${status})."
done

# --- Mount helpers of the selected backends, once every download has completed --------------------

if [ "${INSTALLMOUNTDEPENDENCIES}" = "true" ]; then
  case "${BACKEND}" in
    nfs) install_missing "${nfs_package}" ;;
    fuse) install_missing fuse3 ;;
    both) install_missing "${nfs_package}" fuse3 ;;
  esac
fi

# --- Binaries, once those packages are in place ---------------------------------------------------

install -d -m 0755 "${BIN_DIR}"
for binary in ${binaries}; do
  install -o root -g root -m 0755 "${work_dir}/${binary}" "${BIN_DIR}/${binary}"
done

echo "hf-mount: installed release ${release} in ${BIN_DIR}: ${binaries}"
