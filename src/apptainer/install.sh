#!/usr/bin/env bash
# Installs Apptainer (the non-setuid package `apptainer`, never `apptainer-suid`) with the image's package manager:
# on Fedora from the image's own repositories; on a RHEL derivative from EPEL, enabled through the distribution's
# epel-release package when it is not configured yet, with the EPEL key the package installs checked against its pinned
# full fingerprint; on Ubuntu from the project's PPA at https://ppa.launchpadcontent.net/apptainer/ppa/ubuntu, whose key
# is downloaded from https://keyserver.ubuntu.com and checked against its pinned full fingerprint before it is written
# to /usr/share/keyrings/apptainer-ppa-keyring.gpg and named by /etc/apt/sources.list.d/apptainer.sources; and on
# Debian (amd64 only) from the .deb asset of the newest GitHub release of apptainer/apptainer, resolved through the
# redirect of https://github.com/apptainer/apptainer/releases/latest and downloaded from
# https://github.com/apptainer/apptainer/releases/download, which upstream publishes without checksum or signature
# (the digest https://api.github.com reports is compared when that API answers). Installs curl, ca-certificates, and GnuPG from the image's own repositories
# first, each only when it is missing, and tzdata on Debian and Ubuntu images without /etc/localtime, which Apptainer
# binds into every container. Runs as root at image build time; it takes no options.
set -euo pipefail

readonly PACKAGE="apptainer"
readonly SETUID_PACKAGE="apptainer-suid"
readonly LIBEXEC_DIR="/usr/libexec/apptainer"
readonly LOCALTIME="/etc/localtime"
readonly PPA_URL="https://ppa.launchpadcontent.net/apptainer/ppa/ubuntu"
readonly PPA_FINGERPRINT="F6B0F5193D4F3301EF491FF0AFE36534FC6218AE"
readonly PPA_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${PPA_FINGERPRINT}"
readonly APT_KEYRING="/usr/share/keyrings/apptainer-ppa-keyring.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/apptainer.sources"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly RELEASE_LATEST_URL="https://github.com/apptainer/apptainer/releases/latest"
readonly RELEASE_API_URL="https://api.github.com/repos/apptainer/apptainer/releases/latest"
readonly RELEASE_DOWNLOAD_URL="https://github.com/apptainer/apptainer/releases/download"
readonly EPEL_KEY_DIR="/etc/pki/rpm-gpg"
readonly EPEL_RELEASE_PACKAGE="epel-release"
# The EPEL releases the feature trusts, each with the full fingerprint of its signing key.
readonly EPEL_FINGERPRINT_9="FF8AD1344597106ECE813B918A3872BF3228467C"

export DEBIAN_FRONTEND=noninteractive

os_id=""
os_id_like=""
# Whether apt-get update has run since the package lists were last changed.
apt_lists_fresh=""
os_version_id=""
os_codename=""
# The install path: debian, ubuntu, fedora, or rhel.
family=""
arch=""
# The temporary directory for the key verification and the Debian download; cleanup reads it.
work_dir=""

log() {
  printf 'apptainer: %s\n' "$*"
}

fail() {
  printf 'apptainer: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" && -d "${work_dir}" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      # Stops a gpg-agent that gpg started for this home. The status is ignored: no agent may be running.
      GNUPGHOME="${work_dir}/gnupg" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm --recursive --force "${work_dir}"
  fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Succeeds when the image has gpg under either name a GnuPG package installs.
gpg_installed() {
  if command -v gpg >/dev/null 2>&1; then return 0; fi
  command -v gpg2 >/dev/null 2>&1
}

# Runs gpg, or gpg2 where only that name is installed, without prompts, in the temporary GnuPG home.
run_gpg() {
  if command -v gpg >/dev/null 2>&1; then
    GNUPGHOME="${work_dir}/gnupg" gpg --batch "$@"
  else
    GNUPGHOME="${work_dir}/gnupg" gpg2 --batch "$@"
  fi
}

# Installs packages with apt-get, without prompts or recommended packages.
apt_install() {
  apt-get install --yes --no-install-recommends "$@"
}

# Runs a dnf command that answers every prompt with yes.
dnf_unattended() {
  dnf --assumeyes "$@"
}

# Sets os_id, os_id_like, os_version_id, os_codename, family, and arch, and fails unless the distribution belongs to a
# supported family and the architecture has a package on that family's path.
detect_platform() {
  local distributions distribution
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian, Ubuntu, Fedora, or RHEL-derivative" \
      "image"
  # Read in subshells: /etc/os-release assigns VERSION and other names this script must not take over.
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  # shellcheck source=/dev/null
  os_version_id="$(. /etc/os-release && printf '%s\n' "${VERSION_ID:-}")"
  # shellcheck source=/dev/null
  os_codename="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME:-}")"

  # ID decides first, so Ubuntu, whose ID_LIKE names debian, takes the Ubuntu path; Fedora is recognized by ID alone,
  # because a distribution that is merely Fedora-like (ID_LIKE fedora) has no Fedora repositories. Then the first
  # name in ID_LIKE that belongs to a supported family decides.
  case "${os_id}" in
    ubuntu) family="ubuntu" ;;
    debian) family="debian" ;;
    fedora) family="fedora" ;;
    rhel | centos | almalinux | rocky) family="rhel" ;;
  esac
  if [[ -z "${family}" ]]; then
    read -ra distributions <<<"${os_id_like}"
    for distribution in "${distributions[@]}"; do
      case "${distribution}" in
        ubuntu) family="ubuntu" ;;
        debian) family="debian" ;;
        rhel | centos) family="rhel" ;;
        *) continue ;;
      esac
      break
    done
  fi
  case "${family}" in
    ubuntu | debian)
      if ! command -v apt-get >/dev/null 2>&1; then family=""; fi
      ;;
    fedora | rhel)
      if ! command -v dnf >/dev/null 2>&1; then family=""; fi
      ;;
  esac
  if [[ -z "${family}" ]]; then
    fail "unsupported distribution \"${os_id:-unknown}\" (ID_LIKE \"${os_id_like}\"); use a Debian or Ubuntu image" \
      "with apt, or a Fedora or RHEL-derivative image with dnf"
  fi

  if [[ "${family}" == ubuntu || "${family}" == debian ]]; then
    arch="$(dpkg --print-architecture)" \
      || fail "cannot detect the architecture with dpkg --print-architecture; use an image with a working dpkg"
  else
    arch="$(uname --machine)"
  fi
  case "${family}:${arch}" in
    ubuntu:amd64 | ubuntu:arm64 | fedora:x86_64 | fedora:aarch64 | rhel:x86_64 | rhel:aarch64 | debian:amd64) ;;
    debian:*)
      fail "unsupported architecture \"${arch}\" on Debian: the GitHub release publishes the .deb for amd64 only; use" \
        "an amd64 image, or an Ubuntu, Fedora, or RHEL-derivative image on arm64"
      ;;
    *) fail "unsupported architecture \"${arch}\" on \"${os_id}\"; use an amd64 (x86_64) or arm64 (aarch64) image" ;;
  esac
  if [[ "${family}" == ubuntu && -z "${os_codename}" ]]; then
    fail "cannot read VERSION_CODENAME from /etc/os-release; the PPA is selected by the Ubuntu release's codename"
  fi
  if [[ "${family}" == debian && ! "${os_version_id}" =~ ^[0-9]+$ ]]; then
    fail "cannot read a numeric VERSION_ID from /etc/os-release (found \"${os_version_id}\"); the release asset is" \
      "selected by the Debian release number, so use a released Debian image"
  fi
}

# Installs curl, ca-certificates, and GnuPG from the image's own repositories, each only when it is missing and only
# on the paths that use them: Ubuntu (key download and check), Debian (asset download). On the apt
# family also tzdata when the image has no /etc/localtime (plain ubuntu images): Apptainer binds that file into every
# container by default and fails when it is missing.
install_prerequisites() {
  local missing=()
  case "${family}" in
    ubuntu | debian)
      if ! command -v curl >/dev/null 2>&1; then missing+=(curl); fi
      if ! dpkg --status ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      if [[ "${family}" == ubuntu ]] && ! gpg_installed; then missing+=(gnupg); fi
      if [[ ! -e "${LOCALTIME}" ]]; then missing+=(tzdata); fi
      ;;
    fedora | rhel) ;;
  esac
  if ((${#missing[@]} == 0)); then return; fi

  log "installing the prerequisites ${missing[*]} from the image's repositories"
  apt_update
  apt_install "${missing[@]}" \
    || fail "cannot install the prerequisites ${missing[*]}; check the network and apt-get's messages above"
}

# Refreshes apt's package lists once; a later call after a source change refreshes them again.
apt_update() {
  if [[ -n "${apt_lists_fresh}" ]]; then return; fi
  apt-get update \
    || fail "cannot refresh the package lists; check the network and apt-get's messages above"
  apt_lists_fresh="yes"
}


# Fails unless the key file $1 holds exactly one primary key, a public key with the fingerprint $2; $3 names the key in
# messages.
verify_key_file() {
  local key_file="$1"
  local expected="$2"
  local name="$3"
  local records primaries first kind fingerprint
  if [[ ! -d "${work_dir}/gnupg" ]]; then mkdir --mode 0700 "${work_dir}/gnupg"; fi
  records="$(run_gpg --show-keys --with-colons "${key_file}" 2>/dev/null)" \
    || fail "${key_file} holds no readable OpenPGP key (expected ${name} with fingerprint ${expected})"
  # A primary key is a pub record or, in a secret-key block, a sec record: both count, so that no second key of either
  # kind passes beside the pinned one. grep exits 1 when it counts no line and still prints 0, so its status is ignored.
  primaries="$(grep --count --extended-regexp '^(pub|sec):' <<<"${records}" || true)"
  # The first fpr record after a pub or sec record is that primary key's; subkeys follow their own sub or ssb records.
  # awk keeps the short -F: the Ubuntu base image ships mawk, which has no long form of it.
  first="$(
    awk -F: '$1 == "pub" || $1 == "sec" { kind = $1; next } kind && $1 == "fpr" { print kind, $10; exit }' \
      <<<"${records}"
  )"
  kind="${first%% *}"
  fingerprint="${first#* }"
  if ((primaries != 1)) || [[ "${kind}" != pub || "${fingerprint}" != "${expected}" ]]; then
    fail "${key_file} is not ${name}: expected exactly one primary key, a public key with fingerprint ${expected}," \
      "found ${primaries} primary key(s), public or secret, the first (${kind:-none}) with fingerprint" \
      "\"${fingerprint:-none}\"; check that nothing replaced the key"
  fi
  log "verified ${name} ${expected}"
}

# Ubuntu: downloads the PPA's key, verifies it, exports the pinned key alone into the feature's keyring, and writes
# the PPA's source definition whole at its fixed path.
configure_ppa() {
  local key_file="${work_dir}/ppa.key"
  local exported="${work_dir}/ppa.gpg"
  log "downloading the Apptainer PPA's signing key from ${PPA_KEY_URL}"
  fetch --output "${key_file}" "${PPA_KEY_URL}" \
    || fail "cannot download the Apptainer PPA's signing key from ${PPA_KEY_URL} (expected fingerprint" \
      "${PPA_FINGERPRINT}); check that the build can reach that URL"
  verify_key_file "${key_file}" "${PPA_FINGERPRINT}" "the Apptainer PPA's signing key"
  run_gpg --quiet --import "${key_file}"
  run_gpg --export "${PPA_FINGERPRINT}" >"${exported}"
  [[ -s "${exported}" ]] || fail "exporting key ${PPA_FINGERPRINT} produced nothing; check gpg's messages above"
  log "installing the verified key to ${APT_KEYRING}"
  mkdir --parents "${APT_KEYRING%/*}"
  install --mode 0644 "${exported}" "${APT_KEYRING}"
  log "writing the source definition for ${PPA_URL} ${os_codename} to ${APT_SOURCE}"
  apt_lists_fresh=""
  cat >"${APT_SOURCE}" <<SOURCE
Types: deb
URIs: ${PPA_URL}
Suites: ${os_codename}
Components: main
Signed-By: ${APT_KEYRING}
SOURCE
}

# Ubuntu: installs the package from the PPA.
install_from_ppa() {
  log "installing ${PACKAGE} from the Apptainer PPA for ${os_codename} (${arch})"
  apt_update
  apt_install "${PACKAGE}" \
    || fail "cannot install ${PACKAGE} from the Apptainer PPA; check that the PPA publishes it for ${os_codename} on" \
      "${arch} and apt-get's messages above"
}

# Debian: resolves the newest release from the redirect of the release page, which no rate limit applies to,
# downloads its .deb asset for this Debian release, compares it with the digest GitHub's API reports when the API
# answers and reports one, and installs it with apt-get, which resolves its dependencies from the image's
# repositories. A second install of the version already installed downloads nothing.
install_from_release() {
  local release_json tag_url tag version installed asset asset_url asset_file digest actual
  release_json="${work_dir}/release.json"
  asset_file="${work_dir}/${PACKAGE}.deb"
  log "resolving the newest Apptainer release through ${RELEASE_LATEST_URL}"
  tag_url="$(fetch --output /dev/null --write-out '%{url_effective}' "${RELEASE_LATEST_URL}")" \
    || fail "cannot resolve the newest release from ${RELEASE_LATEST_URL}; check the network"
  tag="${tag_url##*/}"
  [[ "${tag_url}" == "https://github.com/apptainer/apptainer/releases/tag/"* && "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "${RELEASE_LATEST_URL} led to \"${tag_url}\", not a release tag v<MAJOR.MINOR.PATCH>; check that URL"
  version="${tag#v}"
  # ${Version} is a dpkg-query field, not a shell variable.
  # shellcheck disable=SC2016
  installed="$(dpkg-query --show --showformat='${Version}' "${PACKAGE}" 2>/dev/null || true)"
  if [[ "${installed}" == "${version}" ]]; then
    log "${PACKAGE} ${version}, the newest release, is already installed: nothing to download"
    return
  fi
  # Upstream builds one .deb for Debian 11 and 12 and a trixie+ one for Debian 13 and newer.
  if ((os_version_id >= 13)); then
    asset="${PACKAGE}_${version}-trixie+_${arch}.deb"
  else
    asset="${PACKAGE}_${version}_${arch}.deb"
  fi
  asset_url="${RELEASE_DOWNLOAD_URL}/${tag}/${asset}"
  log "downloading ${asset_url}"
  fetch --output "${asset_file}" "${asset_url}" \
    || fail "cannot download ${asset_url}; check that release ${tag} publishes ${asset} for Debian ${os_version_id}" \
      "on ${arch} at https://github.com/apptainer/apptainer/releases/tag/${tag}, and the network"
  # The digest GitHub's API reports for the asset, when the API answers (it is rate-limited for anonymous callers)
  # and reports one: the digest line that follows the asset's name line in its object (the uploader object between
  # them has none). Absent, the download relies on TLS alone.
  digest=""
  if fetch --header 'Accept: application/vnd.github+json' --output "${release_json}" "${RELEASE_API_URL}"; then
    digest="$(
      awk -F'"' -v asset="${asset}" '
        $2 == "name" { found = ($4 == asset) }
        found && $2 == "digest" { print $4; exit }' "${release_json}"
    )"
  else
    log "GitHub's API at ${RELEASE_API_URL} did not answer: no digest to compare"
  fi
  if [[ "${digest}" == sha256:* ]]; then
    actual="$(sha256sum "${asset_file}")"
    actual="${actual%% *}"
    [[ "${actual}" == "${digest#sha256:}" ]] \
      || fail "${asset} does not match the digest GitHub reports (${digest}); check that nothing replaced the download"
    log "verified ${asset} against the digest GitHub reports"
  else
    log "GitHub reports no digest for ${asset}: the download is verified by TLS alone"
  fi
  log "installing ${PACKAGE} ${version} from ${asset}"
  apt_update
  apt_install "${asset_file}" \
    || fail "cannot install ${asset}; check apt-get's messages above for a dependency the image's repositories lack"
}

# Fedora: installs the package from the image's repositories.
install_from_fedora() {
  log "installing ${PACKAGE} from the image's repositories"
  dnf_unattended install "${PACKAGE}" \
    || fail "cannot install ${PACKAGE} from the image's repositories; check the network and dnf's messages above"
}

# RHEL derivative: enables EPEL through the distribution's epel-release package when no EPEL repository is configured,
# verifies the key that package installs against the pinned fingerprint, and installs the package from EPEL.
install_from_epel() {
  local major expected key_file repositories
  local packages=()
  repositories="$(dnf repolist --enabled 2>/dev/null)" \
    || fail "cannot list the enabled repositories with dnf repolist; check dnf's messages above"
  if awk '$1 == "epel" { found = 1 } END { exit !found }' <<<"${repositories}"; then
    log "EPEL is already configured in the image: installing ${PACKAGE} from it as it is"
  else
    major="${os_version_id%%.*}"
    case "${major}" in
      9) expected="${EPEL_FINGERPRINT_9}" ;;
      *)
        fail "no pinned EPEL signing key for release ${major:-unknown} (VERSION_ID \"${os_version_id}\"); this" \
          "feature trusts EPEL 9 only"
        ;;
    esac
    key_file="${EPEL_KEY_DIR}/RPM-GPG-KEY-EPEL-${major}"
    # GnuPG, for the key check, goes in the same transaction: EPEL is not a source until the next one, so nothing is
    # resolved from it before its key is verified, and an image without epel-release changes nothing.
    packages=("${EPEL_RELEASE_PACKAGE}")
    if ! gpg_installed; then packages+=(gnupg2); fi
    log "installing ${packages[*]} from the image's repositories to enable EPEL ${major}"
    dnf_unattended install "${packages[@]}" \
      || fail "cannot install ${packages[*]} from the image's repositories, which this feature needs to enable EPEL;" \
        "use an image whose repositories offer them, or configure EPEL in the image first"
    [[ -r "${key_file}" ]] \
      || fail "${EPEL_RELEASE_PACKAGE} installed no key at ${key_file}; this feature trusts only that file, checked" \
        "against fingerprint ${expected}"
    verify_key_file "${key_file}" "${expected}" "the EPEL ${major} signing key"
  fi
  log "installing ${PACKAGE} from EPEL"
  dnf_unattended install "${PACKAGE}" \
    || fail "cannot install ${PACKAGE} from EPEL; check dnf's messages above, the network, and that no EPEL" \
      "repository the image configured is disabled"
}

# Fails when the setuid package is installed or a setuid file exists under Apptainer's library directory; the feature
# installs the non-setuid package only.
verify_non_setuid() {
  local version setuid_files
  case "${family}" in
    ubuntu | debian)
      # ${Version} is a dpkg-query field, not a shell variable.
      # shellcheck disable=SC2016
      version="$(dpkg-query --show --showformat='${Version}' "${PACKAGE}")" \
        || fail "${PACKAGE} is not installed after the install; check the package manager's messages above"
      if dpkg --status "${SETUID_PACKAGE}" >/dev/null 2>&1; then
        fail "${SETUID_PACKAGE} is installed; this feature installs the non-setuid package only"
      fi
      ;;
    fedora | rhel)
      version="$(rpm --query --queryformat '%{VERSION}-%{RELEASE}' "${PACKAGE}")" \
        || fail "${PACKAGE} is not installed after the install; check the package manager's messages above"
      if rpm --query "${SETUID_PACKAGE}" >/dev/null 2>&1; then
        fail "${SETUID_PACKAGE} is installed; this feature installs the non-setuid package only"
      fi
      ;;
  esac
  if [[ -d "${LIBEXEC_DIR}" ]]; then
    setuid_files="$(find "${LIBEXEC_DIR}" -type f -perm -4000)"
    [[ -z "${setuid_files}" ]] \
      || fail "setuid files under ${LIBEXEC_DIR}: ${setuid_files}; this feature installs the non-setuid package only"
  fi
  log "installed ${PACKAGE} ${version} without setuid"
}

clean_caches() {
  case "${family}" in
    ubuntu | debian)
      log "cleaning the apt caches"
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    fedora | rhel)
      log "cleaning the dnf caches"
      dnf clean all
      ;;
  esac
}

main() {
  detect_platform
  log "installing on ${os_id} ${os_version_id} (${arch}) through the ${family} path"
  trap cleanup EXIT
  work_dir="$(mktemp --directory /tmp/apptainer-install.XXXXXXXXXX)"
  install_prerequisites
  case "${family}" in
    ubuntu)
      configure_ppa
      install_from_ppa
      ;;
    debian) install_from_release ;;
    fedora) install_from_fedora ;;
    rhel) install_from_epel ;;
  esac
  verify_non_setuid
  clean_caches
  log "done"
}

main "$@"
