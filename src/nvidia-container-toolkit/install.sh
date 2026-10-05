#!/usr/bin/env bash
# Installs the NVIDIA Container Toolkit (nvidia-container-toolkit, nvidia-container-toolkit-base,
# libnvidia-container-tools, libnvidia-container1) with the image's package manager from NVIDIA's stable package
# repository at https://nvidia.github.io/libnvidia-container/stable, trusting only NVIDIA's signing key, which is
# downloaded from https://nvidia.github.io/libnvidia-container/gpgkey and checked against its pinned full fingerprint.
# Installs curl, ca-certificates, and GnuPG from the image's own repositories first, each only when it is missing.
# Writes the key to /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg (apt) or
# /etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit (dnf, zypper), where it is also imported into the RPM database,
# the repository definition to /etc/apt/sources.list.d/nvidia-container-toolkit.list,
# /etc/yum.repos.d/nvidia-container-toolkit.repo, or /etc/zypp/repos.d/nvidia-container-toolkit.repo, and registers the
# nvidia runtime in /etc/docker/daemon.json when a Docker daemon is installed. Runs as root at image build time; the
# options `version` and `configureDocker` arrive as VERSION and CONFIGUREDOCKER.
set -euo pipefail

readonly KEY_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
readonly NVIDIA_FINGERPRINT="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
readonly REPO_BASE="https://nvidia.github.io/libnvidia-container/stable"
readonly REPO_ID="nvidia-container-toolkit"
readonly APT_KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
readonly RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit"
readonly DNF_REPO_FILE="/etc/yum.repos.d/nvidia-container-toolkit.repo"
readonly ZYPPER_REPO_FILE="/etc/zypp/repos.d/nvidia-container-toolkit.repo"
readonly DAEMON_JSON="/etc/docker/daemon.json"
readonly APT_LISTS_DIR="/var/lib/apt/lists"
readonly PACKAGES=(
  nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
)

export DEBIAN_FRONTEND=noninteractive

# Unset means the default; an empty value is invalid like any other value the option does not accept.
VERSION="${VERSION-latest}"
CONFIGUREDOCKER="${CONFIGUREDOCKER-true}"

os_id=""
os_id_like=""
# The package manager the install uses: apt, dnf, or zypper.
family=""
arch=""
# The temporary GnuPG home the key is verified in; cleanup reads it.
gnupg_home=""

log() {
  printf 'nvidia-container-toolkit: %s\n' "$*"
}

fail() {
  printf 'nvidia-container-toolkit: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary GnuPG home on every exit, success or failure.
cleanup() {
  if [[ -n "${gnupg_home}" && -d "${gnupg_home}" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      # Stops a gpg-agent that gpg started for this home. The status is ignored: no agent may be running.
      GNUPGHOME="${gnupg_home}" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm --recursive --force "${gnupg_home}"
  fi
}

# Succeeds when the image has gpg under either name a GnuPG package installs.
gpg_installed() {
  if command -v gpg >/dev/null 2>&1; then return 0; fi
  command -v gpg2 >/dev/null 2>&1
}

# Runs gpg, or gpg2 where only that name is installed, without prompts.
run_gpg() {
  if command -v gpg >/dev/null 2>&1; then
    gpg --batch "$@"
  else
    gpg2 --batch "$@"
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

# Runs a zypper command without prompts.
zypper_unattended() {
  zypper --non-interactive "$@"
}

# Fails unless both options hold a value they accept. VERSION becomes readonly in main, after detect_platform has read
# /etc/os-release, which assigns VERSION too.
validate_options() {
  # [[ =~ ]] matches the whole value, so a value holding a newline cannot pass.
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or an exact MAJOR.MINOR.PATCH release such as 1.19.1"
  fi
  if [[ ! "${CONFIGUREDOCKER}" =~ ^(true|false)$ ]]; then
    fail "option configureDocker is \"${CONFIGUREDOCKER}\"; use true or false"
  fi
  readonly CONFIGUREDOCKER
}

# Sets os_id, os_id_like, family, and arch, and fails unless the distribution belongs to a supported family, has that
# family's package manager, and runs on amd64 or arm64.
detect_platform() {
  local distributions distribution
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian-, Ubuntu-, Fedora-, RHEL-," \
      "openSUSE-, or SLES-based image"
  # Read in subshells: /etc/os-release assigns VERSION, which must not replace the option.
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"

  # The first name in ID and ID_LIKE that belongs to a supported family decides.
  read -ra distributions <<<"${os_id} ${os_id_like}"
  for distribution in "${distributions[@]}"; do
    case "${distribution}" in
      debian | ubuntu) family="apt" ;;
      fedora | rhel) family="dnf" ;;
      opensuse | opensuse-* | suse | sles) family="zypper" ;;
      *) continue ;;
    esac
    break
  done
  case "${family}" in
    apt)
      if ! command -v apt-get >/dev/null 2>&1; then family=""; fi
      ;;
    dnf)
      if ! command -v dnf >/dev/null 2>&1; then family=""; fi
      ;;
    zypper)
      if ! command -v zypper >/dev/null 2>&1; then family=""; fi
      ;;
  esac
  if [[ -z "${family}" ]]; then
    fail "unsupported distribution \"${os_id:-unknown}\" (ID_LIKE \"${os_id_like}\"); use a Debian- or Ubuntu-based" \
      "image with apt, a Fedora- or RHEL-based image with dnf, or an openSUSE- or SLES-based image with zypper"
  fi

  if [[ "${family}" == apt ]]; then
    arch="$(dpkg --print-architecture)" \
      || fail "cannot detect the architecture with dpkg --print-architecture; use an image with a working dpkg"
  else
    arch="$(uname --machine)"
  fi
  case "${family}:${arch}" in
    apt:amd64 | apt:arm64 | dnf:x86_64 | dnf:aarch64 | zypper:x86_64 | zypper:aarch64) ;;
    *) fail "unsupported architecture \"${arch}\" on \"${os_id}\"; use an amd64 (x86_64) or arm64 (aarch64) image" ;;
  esac
}

# Installs curl, ca-certificates, and GnuPG from the image's own repositories, each only when it is missing.
install_prerequisites() {
  local missing=()
  local gpg_package=""
  if ! command -v curl >/dev/null 2>&1; then missing+=(curl); fi
  case "${family}" in
    apt)
      if ! dpkg --status ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      gpg_package="gnupg"
      ;;
    dnf)
      if ! rpm --query ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      gpg_package="gnupg2"
      ;;
    zypper)
      if ! rpm --query ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      gpg_package="gpg2"
      ;;
  esac
  if ! gpg_installed; then missing+=("${gpg_package}"); fi
  if ((${#missing[@]} == 0)); then return; fi

  log "installing the prerequisites ${missing[*]} from the image's repositories"
  case "${family}" in
    apt)
      apt-get update \
        || fail "cannot refresh the image's package lists; check the network and apt-get's messages above"
      apt_install "${missing[@]}" \
        || fail "cannot install the prerequisites ${missing[*]}; check the network and apt-get's messages above"
      ;;
    dnf)
      dnf_unattended install "${missing[@]}" \
        || fail "cannot install the prerequisites ${missing[*]}; check the network and dnf's messages above"
      ;;
    zypper)
      zypper_unattended install --no-recommends "${missing[@]}" \
        || fail "cannot install the prerequisites ${missing[*]}; check the network and zypper's messages above"
      ;;
  esac
  if ! gpg_installed; then
    fail "gpg is still missing after installing ${gpg_package}; use an image whose ${gpg_package} package installs" \
      "gpg or gpg2"
  fi
}

# Downloads NVIDIA's signing key, fails unless the file holds exactly one primary key, a public key with the pinned
# fingerprint, and installs the verified key: binary as apt's signed-by keyring, armored and imported for rpm.
install_key() {
  local key_file exported records primaries first kind fingerprint
  gnupg_home="$(mktemp --directory /tmp/nvidia-container-toolkit-gnupg.XXXXXXXXXX)"
  export GNUPGHOME="${gnupg_home}"
  key_file="${gnupg_home}/gpgkey"
  exported="${gnupg_home}/exported"

  log "downloading NVIDIA's signing key from ${KEY_URL}"
  curl --proto '=https' --fail --silent --show-error --location "${KEY_URL}" --output "${key_file}" \
    || fail "cannot download NVIDIA's signing key from ${KEY_URL} (expected fingerprint ${NVIDIA_FINGERPRINT});" \
      "check that the build can reach that URL"
  records="$(run_gpg --show-keys --with-colons "${key_file}" 2>/dev/null)" \
    || fail "the file at ${KEY_URL} holds no readable OpenPGP key (expected fingerprint ${NVIDIA_FINGERPRINT});" \
      "check that nothing between the build and that URL replaces the download"
  # A primary key is a pub record or, in a secret-key block, a sec record: both count, so that no second key of either
  # kind passes beside NVIDIA's. grep exits 1 when it counts no line and still prints 0, so its status is ignored.
  primaries="$(grep --count --extended-regexp '^(pub|sec):' <<<"${records}" || true)"
  # The first fpr record after a pub or sec record is that primary key's; subkeys follow their own sub or ssb records.
  # awk keeps the short -F: the Ubuntu base image ships mawk, which has no long form of it.
  first="$(
    awk -F: '$1 == "pub" || $1 == "sec" { kind = $1; next } kind && $1 == "fpr" { print kind, $10; exit }' \
      <<<"${records}"
  )"
  kind="${first%% *}"
  fingerprint="${first#* }"
  if ((primaries != 1)) || [[ "${kind}" != pub || "${fingerprint}" != "${NVIDIA_FINGERPRINT}" ]]; then
    fail "the key at ${KEY_URL} is not NVIDIA's pinned signing key: expected exactly one primary key, a public key" \
      "with fingerprint ${NVIDIA_FINGERPRINT}, found ${primaries} primary key(s), public or secret, the first" \
      "(${kind:-none}) with fingerprint \"${fingerprint:-none}\"; check that nothing between the build and that URL" \
      "replaces the download"
  fi
  log "verified NVIDIA's signing key ${NVIDIA_FINGERPRINT}"

  run_gpg --quiet --import "${key_file}"
  if [[ "${family}" == apt ]]; then
    log "installing the verified key to ${APT_KEYRING}"
    run_gpg --export "${NVIDIA_FINGERPRINT}" >"${exported}"
    [[ -s "${exported}" ]] || fail "exporting key ${NVIDIA_FINGERPRINT} produced nothing; check gpg's messages above"
    mkdir --parents "${APT_KEYRING%/*}"
    install --mode 0644 "${exported}" "${APT_KEYRING}"
  else
    log "installing the verified key to ${RPM_KEY} and importing it into the RPM database"
    run_gpg --armor --export "${NVIDIA_FINGERPRINT}" >"${exported}"
    [[ -s "${exported}" ]] || fail "exporting key ${NVIDIA_FINGERPRINT} produced nothing; check gpg's messages above"
    mkdir --parents "${RPM_KEY%/*}"
    install --mode 0644 "${exported}" "${RPM_KEY}"
    rpm --import "${RPM_KEY}"
  fi
  # Done with the temporary GnuPG home: nothing after this point reads it. The trap covers the failure paths.
  cleanup
  gnupg_home=""
  unset GNUPGHOME
}

# Writes the one source definition of NVIDIA's stable repository for this architecture, whole, at its fixed path.
write_repository() {
  case "${family}" in
    apt)
      log "writing the repository definition for ${REPO_BASE}/deb/${arch} to ${APT_SOURCE}"
      printf 'deb [signed-by=%s] %s/deb/%s /\n' "${APT_KEYRING}" "${REPO_BASE}" "${arch}" >"${APT_SOURCE}"
      ;;
    dnf)
      log "writing the repository definition for ${REPO_BASE}/rpm/${arch} to ${DNF_REPO_FILE}"
      mkdir --parents "${DNF_REPO_FILE%/*}"
      cat >"${DNF_REPO_FILE}" <<EOF
[${REPO_ID}]
name=NVIDIA Container Toolkit
baseurl=${REPO_BASE}/rpm/${arch}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://${RPM_KEY}
EOF
      ;;
    zypper)
      log "writing the repository definition for ${REPO_BASE}/rpm/${arch} to ${ZYPPER_REPO_FILE}"
      mkdir --parents "${ZYPPER_REPO_FILE%/*}"
      # libzypp checks package signatures only for unsigned repositories unless pkg_gpgcheck is on (zypp.conf(5)).
      cat >"${ZYPPER_REPO_FILE}" <<EOF
[${REPO_ID}]
name=NVIDIA Container Toolkit
baseurl=${REPO_BASE}/rpm/${arch}
enabled=1
gpgcheck=1
repo_gpgcheck=1
pkg_gpgcheck=1
gpgkey=file://${RPM_KEY}
EOF
      ;;
  esac
}

# Installs all four packages together from NVIDIA's stable repository. An exact version asks for package release 1
# (<version>-1), the release the repository publishes each version under; the option itself accepts no release suffix.
install_packages() {
  local specs=("${PACKAGES[@]}")
  local hint="check the network and the package manager's messages above"
  if [[ "${VERSION}" != latest ]]; then
    hint="check that NVIDIA's stable repository offers version ${VERSION} for ${arch}"
    case "${family}" in
      apt | zypper) specs=("${PACKAGES[@]/%/=${VERSION}-1}") ;;
      dnf) specs=("${PACKAGES[@]/%/-${VERSION}-1}") ;;
    esac
  fi

  log "installing ${PACKAGES[*]} at version ${VERSION} from NVIDIA's stable repository ${REPO_BASE}"
  case "${family}" in
    apt)
      apt-get update \
        || fail "cannot refresh the package lists, NVIDIA's stable repository included; check the network and" \
          "apt-get's messages above"
      apt_install --allow-downgrades "${specs[@]}" \
        || fail "cannot install NVIDIA Container Toolkit version ${VERSION} for ${arch}; ${hint}"
      ;;
    dnf)
      dnf_unattended install "${specs[@]}" \
        || fail "cannot install NVIDIA Container Toolkit version ${VERSION} for ${arch}; ${hint}"
      # dnf install leaves an installed package alone, so latest after an older version needs an upgrade.
      if [[ "${VERSION}" == latest ]]; then
        dnf_unattended upgrade "${specs[@]}" \
          || fail "cannot upgrade NVIDIA Container Toolkit to version ${VERSION} for ${arch}; ${hint}"
      fi
      ;;
    zypper)
      zypper_unattended refresh "${REPO_ID}" \
        || fail "cannot refresh NVIDIA's stable repository ${REPO_ID}; check the network and zypper's messages above"
      zypper_unattended install --no-recommends --oldpackage "${specs[@]}" \
        || fail "cannot install NVIDIA Container Toolkit version ${VERSION} for ${arch}; ${hint}"
      ;;
  esac
}

# Prints the installed version-release of the package $1, such as 1.19.1-1; fails when it is not installed.
installed_version() {
  if [[ "${family}" == apt ]]; then
    # ${Version} is a dpkg-query field, not a shell variable.
    # shellcheck disable=SC2016
    dpkg-query --show --showformat='${Version}' "$1"
  else
    rpm --query --queryformat '%{VERSION}-%{RELEASE}' "$1"
  fi
}

# Fails unless all four packages are installed at one version, and at the requested one for an exact version: zypper
# skips a downgrade silently without --oldpackage, so the result is checked, not assumed.
verify_versions() {
  local expected=""
  local first=""
  local package version
  if [[ "${VERSION}" != latest ]]; then expected="${VERSION}-1"; fi
  for package in "${PACKAGES[@]}"; do
    version="$(installed_version "${package}" 2>/dev/null)" \
      || fail "${package} is not installed after installing NVIDIA Container Toolkit version ${VERSION}; check the" \
        "package manager's messages above"
    if [[ -z "${first}" ]]; then first="${version}"; fi
    if [[ "${version}" != "${first}" || (-n "${expected}" && "${version}" != "${expected}") ]]; then
      fail "requested NVIDIA Container Toolkit version ${VERSION}, but ${package} is at ${version} (${PACKAGES[0]} at" \
        "${first}); check the package manager's messages above"
    fi
  done
  log "installed ${PACKAGES[*]} at ${first}"
}

# Registers the nvidia runtime in the Docker daemon's settings when configureDocker is true and a Docker daemon is
# installed.
configure_docker() {
  if [[ "${CONFIGUREDOCKER}" == false ]]; then
    log "configureDocker is disabled: ${DAEMON_JSON} is left unchanged"
    return
  fi
  # sbin directories too: distribution packages install dockerd there, and a build PATH may omit them.
  if ! PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin" command -v dockerd >/dev/null 2>&1; then
    log "no Docker daemon (dockerd) is installed: skipped the Docker configuration"
    return
  fi
  # nvidia-ctk fails on a zero-length file; treat it as an empty object.
  if [[ -f "${DAEMON_JSON}" && ! -s "${DAEMON_JSON}" ]]; then
    log "replacing the zero-length ${DAEMON_JSON} with an empty JSON object"
    printf '{}\n' >"${DAEMON_JSON}"
  fi
  # nvidia-ctk edits its default Docker settings path, which DAEMON_JSON names. It keys the runtime by name, keeps
  # every other setting, and leaves an invalid file unwritten.
  log "registering the nvidia runtime in ${DAEMON_JSON} with nvidia-ctk"
  nvidia-ctk runtime configure --runtime=docker \
    || fail "cannot register the nvidia runtime in ${DAEMON_JSON}; check that the file holds valid JSON"
  log "registered the nvidia runtime in ${DAEMON_JSON}"
}

clean_caches() {
  log "cleaning the package caches of ${family}"
  case "${family}" in
    apt)
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    dnf) dnf clean all ;;
    zypper) zypper_unattended clean --all ;;
  esac
}

main() {
  validate_options
  detect_platform
  # Only now: the /etc/os-release subshells in detect_platform would fail on a readonly VERSION.
  readonly VERSION
  log "installing version ${VERSION} on ${os_id} (${arch}) with ${family}"
  trap cleanup EXIT
  install_prerequisites
  install_key
  write_repository
  install_packages
  verify_versions
  configure_docker
  clean_caches
  log "done"
}

main "$@"
