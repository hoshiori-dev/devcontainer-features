#!/usr/bin/env bash
# Builds distrobuilder from upstream's release source and installs it to /usr/local/bin/distrobuilder. The source
# archive distrobuilder-<version>.tar.gz comes from https://github.com/lxc/distrobuilder/releases and is used only
# when its detached signature is a good one by the release manager's key, pinned by fingerprint and fetched from
# https://github.com/stgraber.gpg. The build uses the Go release the source's go.mod names, downloaded from
# https://dl.google.com/go/ and checked against the SHA-256 checksum published beside it; it runs from the modules
# vendored in the source, without network access, in a temporary directory that is removed with the toolchain at the
# end. The installed release is recorded in /usr/local/share/lxc-distrobuilder/version. From the image's own
# repositories it installs, when missing: curl, CA certificates, GnuPG, tar, gzip, a C compiler, and the C
# library's headers for the download and the build; debootstrap, rsync, the SquashFS tools, and xz, which
# distrobuilder runs; and the tools of the options vmSupport and windowsSupport.
# Runs as root at image build time; options arrive as environment variables:
#   version: VERSION
#   vmSupport: VMSUPPORT
#   windowsSupport: WINDOWSSUPPORT
set -euo pipefail

readonly MIN_VERSION="3.3.1"
readonly RELEASES_URL="https://github.com/lxc/distrobuilder/releases"
readonly LATEST_URL="https://github.com/lxc/distrobuilder/releases/latest"
readonly KEY_URL="https://github.com/stgraber.gpg"
# The primary fingerprint of the key upstream's release manager signs releases with
# (openspec/specs/lxc-distrobuilder/spec.md, "Release signature"). Only a signature by this key is accepted.
readonly SIGNING_FINGERPRINT="602F567663E593BCBD14F338C638974D64792D67"
readonly GO_DOWNLOAD_URL="https://dl.google.com/go"
# The build tags upstream's Makefile sets.
readonly BUILD_TAGS="containers_image_storage_stub,containers_image_docker_daemon_stub,containers_image_openpgp"
readonly TARGET="/usr/local/bin/distrobuilder"
# The executable is staged next to the target, so the rename over it stays on one file system.
readonly STAGING_TEMPLATE="/usr/local/bin/.lxc-distrobuilder.XXXXXX"
readonly SHARE_DIR="/usr/local/share/lxc-distrobuilder"
readonly VERSION_FILE="/usr/local/share/lxc-distrobuilder/version"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

export DEBIAN_FRONTEND=noninteractive

VERSION="${VERSION-latest}"
VMSUPPORT="${VMSUPPORT-false}"
WINDOWSSUPPORT="${WINDOWSSUPPORT-false}"

# The release to install, without a leading "v"; empty until "latest" is resolved.
version=""
# The image's architecture as dpkg and Go both name it: amd64 or arm64.
arch=""
work_dir=""
staged=""

log() {
  printf 'lxc-distrobuilder: %s\n' "$*"
}

fail() {
  printf 'lxc-distrobuilder: error: %s\n' "$*" >&2
  exit 1
}

# Removes the staged executable and the work directory on every exit, success or failure. Go's module cache is
# read-only, so the directory is made writable first.
cleanup() {
  if [[ -n "${staged}" ]]; then rm --force "${staged}"; fi
  if [[ -n "${work_dir}" ]]; then
    chmod --recursive u+w "${work_dir}" 2>/dev/null || true
    rm --recursive --force "${work_dir}"
  fi
}

# Runs curl over HTTPS only, on every hop including redirects, with failing HTTP statuses as errors. --retry 3
# handles a known failure mode: a transient network error.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Downloads URL $1 to file $2, following redirects: GitHub serves release assets from its asset host. Fails with the
# remaining arguments as the message when the download fails.
download() {
  local url="$1"
  local file="$2"
  log "downloading ${url}"
  fetch --location --output "${file}" "${url}" || fail "${@:3}"
}

# Prints $1 without a leading "v" when it is v?MAJOR.MINOR.PATCH of decimal numbers without leading zeros, as
# release tags are; else returns 1.
normalize_version() {
  local value="${1#v}"
  [[ "${value}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || return 1
  printf '%s\n' "${value}"
}

# Succeeds when normalized version $1 is at or above normalized version $2.
version_at_least() {
  local a b index
  IFS=. read -ra a <<<"$1"
  IFS=. read -ra b <<<"$2"
  for index in 0 1 2; do
    if ((a[index] > b[index])); then return 0; fi
    if ((a[index] < b[index])); then return 1; fi
  done
  return 0
}

# Fails unless the options have accepted values. Sets version to the release without its leading "v", and leaves it
# empty for "latest".
validate_options() {
  if [[ "${VERSION}" != latest ]]; then
    if ! version="$(normalize_version "${VERSION}")"; then
      fail "option version is \"${VERSION}\"; use \"latest\" or a release version MAJOR.MINOR.PATCH such as 3.4.0," \
        "with or without a leading \"v\""
    fi
    if ! version_at_least "${version}" "${MIN_VERSION}"; then
      fail "option version is ${version}, below the minimum ${MIN_VERSION}; set version to ${MIN_VERSION} or later"
    fi
  fi
  if [[ ! "${VMSUPPORT}" =~ ^(true|false)$ ]]; then
    fail "option vmSupport is \"${VMSUPPORT}\"; use true or false"
  fi
  if [[ ! "${WINDOWSSUPPORT}" =~ ^(true|false)$ ]]; then
    fail "option windowsSupport is \"${WINDOWSSUPPORT}\"; use true or false"
  fi
  readonly VMSUPPORT WINDOWSSUPPORT
}

# Sets arch; fails on an unsupported distribution or architecture before anything changes. Runs before VERSION
# becomes readonly: /etc/os-release assigns it too.
detect_platform() {
  local os_id
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in
    debian | ubuntu) ;;
    *) fail "unsupported distribution \"${os_id:-unknown}\"; use a Debian or Ubuntu image" ;;
  esac
  command -v apt-get >/dev/null 2>&1 \
    || fail "distribution \"${os_id}\" is supported, but the image has no apt-get; use an image that has it"
  command -v dpkg >/dev/null 2>&1 \
    || fail "distribution \"${os_id}\" is supported, but the image has no dpkg; use an image that has it"
  # The architecture of the image's packages, which the C compiler targets; Go names amd64 and arm64 the same way.
  arch="$(dpkg --print-architecture)"
  case "${arch}" in
    amd64 | arm64) ;;
    *) fail "unsupported architecture \"${arch}\"; the feature builds distrobuilder for amd64 and arm64 only" ;;
  esac
}

# Fails when TARGET exists but is not a regular file: a rename over a directory would put the executable inside it,
# and a symbolic link would be replaced, not followed.
check_target() {
  if [[ -e "${TARGET}" || -L "${TARGET}" ]]; then
    if [[ ! -f "${TARGET}" || -L "${TARGET}" ]]; then
      fail "${TARGET} exists but is not a regular file; remove it, then install again"
    fi
  fi
}

# Installs, from the repositories the image configures, what the image lacks of: the tools the download and the
# build need, the tools distrobuilder runs to build container images, and the tools of the options. A tool counts as
# present when its command is on PATH.
install_packages() {
  local packages=()
  if ! command -v curl >/dev/null 2>&1; then packages+=(curl); fi
  if [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then packages+=(ca-certificates); fi
  if ! command -v gpg >/dev/null 2>&1; then packages+=(gpg); fi
  if ! command -v tar >/dev/null 2>&1; then packages+=(tar); fi
  if ! command -v gzip >/dev/null 2>&1; then packages+=(gzip); fi
  if ! command -v gcc >/dev/null 2>&1; then packages+=(gcc); fi
  if [[ ! -e /usr/include/stdlib.h ]]; then packages+=(libc6-dev); fi
  if ! command -v debootstrap >/dev/null 2>&1; then packages+=(debootstrap); fi
  if ! command -v rsync >/dev/null 2>&1; then packages+=(rsync); fi
  if ! command -v mksquashfs >/dev/null 2>&1; then packages+=(squashfs-tools); fi
  if ! command -v xz >/dev/null 2>&1; then packages+=(xz-utils); fi
  if [[ "${VMSUPPORT}" == true ]]; then
    if ! command -v mkfs.btrfs >/dev/null 2>&1; then packages+=(btrfs-progs); fi
    if ! command -v mkfs.vfat >/dev/null 2>&1; then packages+=(dosfstools); fi
    if ! command -v mkfs.ext4 >/dev/null 2>&1; then packages+=(e2fsprogs); fi
    if ! command -v sgdisk >/dev/null 2>&1; then packages+=(gdisk); fi
    if ! command -v qemu-img >/dev/null 2>&1; then packages+=(qemu-utils); fi
    if ! command -v udevadm >/dev/null 2>&1; then packages+=(udev); fi
  fi
  if [[ "${WINDOWSSUPPORT}" == true ]]; then
    if ! command -v hivexregedit >/dev/null 2>&1; then packages+=(libwin-hivex-perl); fi
    if ! command -v wimlib-imagex >/dev/null 2>&1; then packages+=(wimtools); fi
    if ! command -v genisoimage >/dev/null 2>&1; then packages+=(genisoimage); fi
  fi
  if ((${#packages[@]} == 0)); then return 0; fi
  log "installing ${packages[*]} from the image's apt repositories"
  apt-get update \
    || fail "apt-get update failed; check the image's apt sources and the network"
  apt-get install --yes --no-install-recommends "${packages[@]}" \
    || fail "apt-get could not install ${packages[*]}; check the messages above"
  apt-get clean
  rm --recursive --force "${APT_LISTS_DIR:?}"/*
}

# Sets version to the release the latest-release link redirects to, read without following the redirect. Upstream
# signs nothing about the link, so it relies on TLS alone; the release it names is still verified like an explicit
# version (the feature's spec, "Release metadata trust").
resolve_latest() {
  local location tag
  location="$(fetch --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")" \
    || fail "cannot read ${LATEST_URL}; check network access to github.com, or set version to a release"
  [[ -n "${location}" ]] || fail "${LATEST_URL} did not redirect to a release; set version to a release"
  log "read the latest release from ${LATEST_URL}: ${location}"
  # The redirect is not followed, so --proto-redir does not apply to it: only a release page of the same repository
  # over HTTPS is accepted. The tag is the rest of the URL, without a query, a fragment, or a trailing slash.
  [[ "${location}" == "${RELEASES_URL}/tag/"* ]] \
    || fail "${LATEST_URL} redirects to \"${location}\", not to a release page under ${RELEASES_URL}/tag/; set" \
      "version to a release"
  tag="${location#"${RELEASES_URL}/tag/"}"
  tag="${tag%%[?#]*}"
  tag="${tag%/}"
  if ! version="$(normalize_version "${tag}")" || ! version_at_least "${version}" "${MIN_VERSION}"; then
    fail "the latest release is \"${tag}\", not a release version MAJOR.MINOR.PATCH at or above ${MIN_VERSION}; set" \
      "version to a release"
  fi
}

# Succeeds when the recorded release is the selected one and the executable exists. The record decides, not the
# executable: distrobuilder cannot print its version in an image build, which lacks the capability it needs.
already_installed() {
  local recorded
  [[ -f "${TARGET}" && -r "${VERSION_FILE}" ]] || return 1
  recorded="$(<"${VERSION_FILE}")"
  [[ "${recorded}" == "${version}" ]]
}

# Downloads the source archive, its detached signature, and the release manager's public keys into the work
# directory, and fails unless the signature is good and made by the key whose primary fingerprint is
# SIGNING_FINGERPRINT. The keyring lives in the work directory, and no option weakens GnuPG's checks.
verify_source() {
  local archive="distrobuilder-${version}.tar.gz"
  local url="${RELEASES_URL}/download/v${version}/${archive}"
  local signers signer members member
  download "${url}" "${work_dir}/${archive}" \
    "cannot download ${url}; check that release ${version} exists and that github.com is reachable"
  download "${url}.asc" "${work_dir}/${archive}.asc" \
    "verification failed: cannot download ${url}.asc, the signature of the source archive; retry the build, and set" \
    "version to another release if it persists"
  download "${KEY_URL}" "${work_dir}/keys.asc" \
    "cannot download ${KEY_URL}; check network access to github.com"
  # The keys are turned into a keyring file and used in place, not imported: importing starts gpg-agent, which the
  # minimal gpg package does not include, and verifying needs no agent.
  mkdir --mode 0700 "${work_dir}/gnupg"
  gpg --batch --homedir "${work_dir}/gnupg" --output "${work_dir}/keys.gpg" --dearmor "${work_dir}/keys.asc" \
    2>"${work_dir}/gpg-key.log" \
    || fail "cannot read the keys from ${KEY_URL}: $(<"${work_dir}/gpg-key.log")"
  if ! gpg --batch --homedir "${work_dir}/gnupg" --no-default-keyring --keyring "${work_dir}/keys.gpg" \
    --status-file "${work_dir}/gpg-status" --verify "${work_dir}/${archive}.asc" "${work_dir}/${archive}" \
    2>"${work_dir}/gpg-verify.log"; then
    fail "verification failed: the signature of ${url} does not verify: $(<"${work_dir}/gpg-verify.log")"
  fi
  # Every signature must be good and made by the pinned primary key; the last field of VALIDSIG is the primary
  # key's fingerprint.
  if grep --quiet --extended-regexp '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG) ' \
    "${work_dir}/gpg-status"; then
    fail "verification failed: ${url} carries a signature that is not good"
  fi
  signers="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "${work_dir}/gpg-status")"
  [[ -n "${signers}" ]] || fail "verification failed: ${url} carries no valid signature"
  while IFS= read -r signer; do
    [[ "${signer}" == "${SIGNING_FINGERPRINT}" ]] \
      || fail "verification failed: ${url} is signed by ${signer}, not by the release key ${SIGNING_FINGERPRINT}"
  done <<<"${signers}"
  log "verified the signature of ${archive} by ${SIGNING_FINGERPRINT}"
  # The signature says who made the archive, not which release it is: every member must lie in the directory named
  # after the selected release, so that an archive of another release, validly signed, is not built in its place.
  members="$(tar --list --gzip --file "${work_dir}/${archive}")" \
    || fail "cannot list ${archive}; set version to another release"
  while IFS= read -r member; do
    [[ "${member}" == "distrobuilder-${version}" || "${member}" == "distrobuilder-${version}/"* ]] \
      || fail "verification failed: ${archive} holds \"${member}\" outside distrobuilder-${version}/, so it is not" \
        "the source of release ${version}"
  done <<<"${members}"
  mkdir "${work_dir}/source"
  tar --extract --gzip --file "${work_dir}/${archive}" --directory "${work_dir}/source" --strip-components 1 \
    --no-same-owner \
    || fail "cannot unpack ${archive}; set version to another release"
  [[ -f "${work_dir}/source/go.mod" && -d "${work_dir}/source/vendor" ]] \
    || fail "${archive} holds no go.mod or no vendored modules, so it cannot be built without network access; set" \
      "version to another release"
}

# Downloads the Go release the verified source's go.mod names and its published checksum, and unpacks it into the
# work directory only when the archive's SHA-256 digest equals the checksum.
fetch_toolchain() {
  local go_version archive url expected actual
  # The first line of go.mod of the form "go MAJOR.MINOR.PATCH".
  go_version="$(sed --quiet --regexp-extended 's/^go ([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' \
    "${work_dir}/source/go.mod")"
  go_version="${go_version%%$'\n'*}"
  [[ -n "${go_version}" ]] \
    || fail "go.mod of release ${version} names no Go release of the form MAJOR.MINOR.PATCH; set version to another" \
      "release"
  archive="go${go_version}.linux-${arch}.tar.gz"
  url="${GO_DOWNLOAD_URL}/${archive}"
  download "${url}" "${work_dir}/${archive}" \
    "cannot download ${url}, the Go release go.mod of release ${version} names; check network access to dl.google.com"
  download "${url}.sha256" "${work_dir}/${archive}.sha256" \
    "verification failed: cannot download ${url}.sha256, the checksum of the Go archive; retry the build"
  expected="$(<"${work_dir}/${archive}.sha256")"
  [[ "${expected}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "verification failed: ${url}.sha256 does not hold one SHA-256 digest"
  actual="$(sha256sum "${work_dir}/${archive}")"
  actual="${actual%% *}"
  [[ "${actual}" == "${expected}" ]] \
    || fail "verification failed: ${archive} has the SHA-256 digest ${actual}, and ${url}.sha256 names ${expected};" \
      "retry the build"
  log "verified ${archive} against its published checksum"
  tar --extract --gzip --file "${work_dir}/${archive}" --directory "${work_dir}" --no-same-owner \
    || fail "cannot unpack ${archive}; retry the build"
  [[ -x "${work_dir}/go/bin/go" ]] || fail "${archive} holds no go/bin/go; retry the build"
}

# Builds distrobuilder from the vendored modules of the verified source, in an environment that holds nothing of the
# build's own: the toolchain downloads no module and no other toolchain, runs no version control tool of the image
# (-buildvcs=false), and keeps its caches in the work directory.
build() {
  log "building distrobuilder ${version} from its vendored modules, without network access"
  mkdir "${work_dir}/home" "${work_dir}/gocache" "${work_dir}/gopath"
  (
    cd "${work_dir}/source" && env --ignore-environment \
      PATH="${work_dir}/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      HOME="${work_dir}/home" GOROOT="${work_dir}/go" GOCACHE="${work_dir}/gocache" GOPATH="${work_dir}/gopath" \
      GOMODCACHE="${work_dir}/gopath/pkg/mod" GOFLAGS=-mod=vendor GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local \
      GOTELEMETRY=off GOWORK=off GOENV=off CGO_ENABLED=1 \
      go build -buildvcs=false -tags "${BUILD_TAGS}" -o "${work_dir}/distrobuilder" ./distrobuilder
  ) || fail "the build of distrobuilder ${version} failed; check the messages above, and set version to another" \
    "release if it persists"
  [[ -f "${work_dir}/distrobuilder" ]] || fail "the build of distrobuilder ${version} produced no executable"
}

# Stages the executable next to TARGET, renames it over TARGET, so the target is replaced in one step, and records
# the release.
install_binary() {
  mkdir --parents "${TARGET%/*}" "${SHARE_DIR}"
  staged="$(mktemp "${STAGING_TEMPLATE}")"
  cp "${work_dir}/distrobuilder" "${staged}"
  chmod 0755 "${staged}"
  mv --force "${staged}" "${TARGET}"
  staged=""
  printf '%s\n' "${version}" >"${VERSION_FILE}"
  chmod 0644 "${VERSION_FILE}"
  log "installed distrobuilder ${version} to ${TARGET} and recorded the release in ${VERSION_FILE}"
}

main() {
  validate_options
  detect_platform
  readonly VERSION
  trap cleanup EXIT
  # Every file and directory the install creates is readable by every user, whatever umask the build runs with.
  umask 022
  check_target
  install_packages
  if [[ "${VERSION}" == latest ]]; then resolve_latest; fi
  if already_installed; then
    log "distrobuilder ${version} is already installed at ${TARGET}; leaving it unchanged"
    return 0
  fi
  work_dir="$(mktemp --directory)"
  verify_source
  fetch_toolchain
  build
  install_binary
}

main "$@"
