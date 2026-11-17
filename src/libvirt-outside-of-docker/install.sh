#!/usr/bin/env bash
# Installs the libvirt client (virsh) and, as the options say, virt-install and qemu-img, with the image's package
# manager from the repositories the image already configures: libvirt-clients, virtinst, and qemu-utils on Debian and
# Ubuntu; libvirt-client, virt-install, and qemu-img on Fedora. Records the remote user in
# /usr/local/share/libvirt-outside-of-docker/settings and installs the two start scripts beside it: align_group.sh,
# the feature's entrypoint, and check.sh, its postStartCommand. Installs no libvirt daemon and downloads nothing else.
# Runs as root at image build time; options arrive as environment variables:
#   virtInstall: VIRTINSTALL
#   qemuImg: QEMUIMG
set -euo pipefail

readonly SHARE_DIR="/usr/local/share/libvirt-outside-of-docker"
readonly SETTINGS_FILE="/usr/local/share/libvirt-outside-of-docker/settings"
readonly ALIGN_SCRIPT="/usr/local/share/libvirt-outside-of-docker/align_group.sh"
readonly CHECK_SCRIPT="/usr/local/share/libvirt-outside-of-docker/check.sh"
# The share directory of the libvirt-in-docker feature, whose presence means that feature is installed.
readonly IN_DOCKER_SHARE_DIR="/usr/local/share/libvirt-in-docker"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

export DEBIAN_FRONTEND=noninteractive

VIRTINSTALL="${VIRTINSTALL-true}"
QEMUIMG="${QEMUIMG-false}"

os_id=""
os_id_like=""
# The install path: apt or dnf.
family=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf 'libvirt-outside-of-docker: %s\n' "$*"
}

fail() {
  printf 'libvirt-outside-of-docker: error: %s\n' "$*" >&2
  exit 1
}

validate_options() {
  if [[ ! "${VIRTINSTALL}" =~ ^(true|false)$ ]]; then
    fail "option virtInstall is \"${VIRTINSTALL}\"; use true or false"
  fi
  if [[ ! "${QEMUIMG}" =~ ^(true|false)$ ]]; then
    fail "option qemuImg is \"${QEMUIMG}\"; use true or false"
  fi
  readonly VIRTINSTALL QEMUIMG
}

# Sets os_id, os_id_like, and family; fails on an unsupported distribution before anything changes.
detect_platform() {
  local distributions distribution
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a Debian, Ubuntu, or Fedora image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  case "${os_id}" in
    debian | ubuntu) family="apt" ;;
    fedora) family="dnf" ;;
  esac
  if [[ -z "${family}" ]]; then
    read -ra distributions <<<"${os_id_like}"
    for distribution in "${distributions[@]}"; do
      case "${distribution}" in
        debian | ubuntu) family="apt" ;;
        *) continue ;;
      esac
      break
    done
  fi
  case "${family}" in
    apt)
      if ! command -v apt-get >/dev/null 2>&1; then family=""; fi
      ;;
    dnf)
      if ! command -v dnf >/dev/null 2>&1; then family=""; fi
      ;;
  esac
  if [[ -z "${family}" ]]; then
    fail "unsupported distribution \"${os_id:-unknown}\" (ID_LIKE \"${os_id_like}\"); use a Debian or Ubuntu image" \
      "with apt, or a Fedora image with dnf"
  fi
}

# Fails when the libvirt-in-docker feature is installed: its daemon and a mount of the host's /run/libvirt would
# share one directory.
check_other_feature() {
  if [[ -e "${IN_DOCKER_SHARE_DIR}" ]]; then
    fail "the libvirt-in-docker feature is installed in this image (${IN_DOCKER_SHARE_DIR} exists);" \
      "libvirt-outside-of-docker and libvirt-in-docker are alternatives, so remove one of them from devcontainer.json"
  fi
}

install_packages() {
  local packages=()
  case "${family}" in
    apt)
      packages+=(libvirt-clients)
      if [[ "${VIRTINSTALL}" == true ]]; then packages+=(virtinst); fi
      if [[ "${QEMUIMG}" == true ]]; then packages+=(qemu-utils); fi
      log "installing ${packages[*]} from the image's apt repositories"
      apt-get update \
        || fail "apt-get update failed; check the image's apt sources and the network"
      apt-get install --yes --no-install-recommends "${packages[@]}" \
        || fail "apt-get could not install ${packages[*]}; check the messages above"
      ;;
    dnf)
      packages+=(libvirt-client)
      if [[ "${VIRTINSTALL}" == true ]]; then packages+=(virt-install); fi
      if [[ "${QEMUIMG}" == true ]]; then packages+=(qemu-img); fi
      log "installing ${packages[*]} from the image's dnf repositories"
      dnf --assumeyes --setopt=install_weak_deps=False install "${packages[@]}" \
        || fail "dnf could not install ${packages[*]}; check the messages above"
      ;;
  esac
}

# Writes the remote user's name, which align_group.sh reads at every start, and installs the two start scripts.
install_start_scripts() {
  local remote_user="${_REMOTE_USER:-root}"
  mkdir --parents "${SHARE_DIR}"
  log "recording the remote user \"${remote_user}\" in ${SETTINGS_FILE}"
  printf 'remoteUser=%s\n' "${remote_user}" >"${SETTINGS_FILE}"
  chmod 0644 "${SETTINGS_FILE}"
  log "installing the entrypoint to ${ALIGN_SCRIPT} and the start check to ${CHECK_SCRIPT}"
  install --mode 0755 "${script_dir}/scripts/align_group.sh" "${ALIGN_SCRIPT}"
  install --mode 0755 "${script_dir}/scripts/check.sh" "${CHECK_SCRIPT}"
}

clean_caches() {
  case "${family}" in
    apt)
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    dnf) dnf clean all ;;
  esac
}

main() {
  validate_options
  detect_platform
  check_other_feature
  install_packages
  install_start_scripts
  clean_caches
  log "done"
}

main "$@"
