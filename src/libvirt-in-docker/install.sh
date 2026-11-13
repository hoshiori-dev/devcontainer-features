#!/usr/bin/env bash
# Installs the libvirt daemon, QEMU, and the libvirt client tools with the image's package manager from the
# repositories the image already configures, and prepares them to run in a privileged container without systemd.
# Packages on Debian and Ubuntu: libvirt-daemon-system, libvirt-daemon-config-network, libvirt-clients, virtinst,
# qemu-utils, dnsmasq-base, iptables, and qemu-system-x86 with ovmf (amd64) or qemu-system-arm with qemu-efi-aarch64
# (arm64). On Fedora: the libvirt-daemon-driver packages for QEMU, networks, node devices, network filters, secrets,
# and storage, libvirt-daemon-log, libvirt-daemon-config-network, libvirt-client, virt-install, qemu-kvm-core,
# qemu-img, dnsmasq, nftables, and edk2-ovmf (amd64) or edk2-aarch64 (arm64). With the option swtpm: swtpm and
# swtpm-tools. Writes one marked block to /etc/libvirt/qemu.conf and one to the configuration file of each daemon the
# feature starts, removes the autostart mark of the default network, adds the remote user to the libvirt group,
# records the settings in /usr/local/share/libvirt-in-docker/settings, and installs the two start scripts beside it:
# start.sh, the feature's entrypoint, and check.sh, its postStartCommand. Downloads nothing else.
# Runs as root at image build time; options arrive as environment variables:
#   defaultNetwork: DEFAULTNETWORK
#   swtpm: SWTPM
set -euo pipefail

readonly SHARE_DIR="/usr/local/share/libvirt-in-docker"
readonly SETTINGS_FILE="/usr/local/share/libvirt-in-docker/settings"
readonly START_SCRIPT="/usr/local/share/libvirt-in-docker/start.sh"
readonly CHECK_SCRIPT="/usr/local/share/libvirt-in-docker/check.sh"
# The share directory of the libvirt-outside-of-docker feature, whose presence means that feature is installed.
readonly OUTSIDE_SHARE_DIR="/usr/local/share/libvirt-outside-of-docker"
readonly LIBVIRT_CONFIG_DIR="/etc/libvirt"
readonly QEMU_CONF="/etc/libvirt/qemu.conf"
# The mark that makes libvirt start the default network by itself; the feature's entrypoint starts it instead.
readonly DEFAULT_NETWORK_AUTOSTART="/etc/libvirt/qemu/networks/autostart/default.xml"
readonly LIBVIRT_GROUP="libvirt"
readonly BLOCK_BEGIN="# BEGIN libvirt-in-docker feature: this block is replaced at each install of the feature"
readonly BLOCK_END="# END libvirt-in-docker feature"
# The daemons of the modular layout, which a distribution without libvirtd runs.
readonly MODULAR_DAEMONS=(virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtnwfilterd)
readonly APT_LISTS_DIR="/var/lib/apt/lists"

export DEBIAN_FRONTEND=noninteractive

DEFAULTNETWORK="${DEFAULTNETWORK-true}"
SWTPM="${SWTPM-false}"
# The remote user, which the Dev Container tooling names in _REMOTE_USER; root when it names none.
readonly REMOTE_USER_NAME="${_REMOTE_USER:-root}"

os_id=""
os_id_like=""
# The install path: apt or dnf.
family=""
# The container's architecture: amd64 or arm64.
arch=""
# The daemon layout the distribution's packages provide: monolithic (libvirtd) or modular.
layout=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf 'libvirt-in-docker: %s\n' "$*"
}

fail() {
  printf 'libvirt-in-docker: error: %s\n' "$*" >&2
  exit 1
}

validate_options() {
  if [[ ! "${DEFAULTNETWORK}" =~ ^(true|false)$ ]]; then
    fail "option defaultNetwork is \"${DEFAULTNETWORK}\"; use true or false"
  fi
  if [[ ! "${SWTPM}" =~ ^(true|false)$ ]]; then
    fail "option swtpm is \"${SWTPM}\"; use true or false"
  fi
  readonly DEFAULTNETWORK SWTPM
}

# Sets os_id, os_id_like, family, and arch; fails on an unsupported distribution or architecture before anything
# changes.
detect_platform() {
  local distributions distribution machine
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
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) fail "unsupported architecture \"${machine}\"; the feature installs QEMU for amd64 and arm64 only" ;;
  esac
}

# Fails when the libvirt-outside-of-docker feature is installed: a mount of the host's /run/libvirt and this
# feature's daemon would share one directory.
check_other_feature() {
  if [[ -e "${OUTSIDE_SHARE_DIR}" ]]; then
    fail "the libvirt-outside-of-docker feature is installed in this image (${OUTSIDE_SHARE_DIR} exists);" \
      "libvirt-in-docker and libvirt-outside-of-docker are alternatives, so remove one of them from devcontainer.json"
  fi
}

install_packages() {
  local packages=()
  case "${family}" in
    apt)
      packages+=(libvirt-daemon-system libvirt-daemon-config-network libvirt-clients virtinst qemu-utils)
      packages+=(dnsmasq-base iptables)
      case "${arch}" in
        amd64) packages+=(qemu-system-x86 ovmf) ;;
        arm64) packages+=(qemu-system-arm qemu-efi-aarch64) ;;
      esac
      if [[ "${SWTPM}" == true ]]; then packages+=(swtpm swtpm-tools); fi
      log "installing ${packages[*]} from the image's apt repositories"
      apt-get update \
        || fail "apt-get update failed; check the image's apt sources and the network"
      apt-get install --yes --no-install-recommends "${packages[@]}" \
        || fail "apt-get could not install ${packages[*]}; check the messages above"
      ;;
    dnf)
      packages+=(libvirt-daemon-driver-qemu libvirt-daemon-driver-network libvirt-daemon-driver-nodedev)
      packages+=(libvirt-daemon-driver-nwfilter libvirt-daemon-driver-secret libvirt-daemon-driver-storage-core)
      packages+=(libvirt-daemon-log libvirt-daemon-config-network libvirt-client virt-install)
      packages+=(qemu-kvm-core qemu-img dnsmasq nftables)
      case "${arch}" in
        amd64) packages+=(edk2-ovmf) ;;
        arm64) packages+=(edk2-aarch64) ;;
      esac
      if [[ "${SWTPM}" == true ]]; then packages+=(swtpm swtpm-tools); fi
      log "installing ${packages[*]} from the image's dnf repositories"
      dnf --assumeyes --setopt=install_weak_deps=False install "${packages[@]}" \
        || fail "dnf could not install ${packages[*]}; check the messages above"
      ;;
  esac
}

# Sets layout from the daemons the packages installed.
detect_layout() {
  local daemon
  if command -v libvirtd >/dev/null 2>&1; then
    layout="monolithic"
  else
    for daemon in "${MODULAR_DAEMONS[@]}"; do
      command -v "${daemon}" >/dev/null 2>&1 \
        || fail "the packages installed neither libvirtd nor ${daemon}; use an image listed in" \
          "test/libvirt-in-docker/compatibility.json"
    done
    layout="modular"
  fi
  command -v virtlogd >/dev/null 2>&1 \
    || fail "the packages installed no virtlogd; use an image listed in test/libvirt-in-docker/compatibility.json"
  log "the distribution's daemon layout is ${layout}"
}

# Replaces the feature's block in the configuration file $1 with the lines read from standard input, creating the
# file when it does not exist. Everything outside the block stays as it is.
write_block() {
  local file="$1"
  local kept
  kept="$(mktemp)"
  if [[ -e "${file}" ]]; then
    sed "/^${BLOCK_BEGIN}\$/,/^${BLOCK_END}\$/d" "${file}" >"${kept}"
  fi
  {
    cat "${kept}"
    printf '%s\n' "${BLOCK_BEGIN}"
    cat
    printf '%s\n' "${BLOCK_END}"
  } >"${file}.libvirt-in-docker"
  rm --force "${kept}"
  chmod 0644 "${file}.libvirt-in-docker"
  mv --force "${file}.libvirt-in-docker" "${file}"
}

# Configures the QEMU driver for a container without systemd: no security driver, QEMU as root, no ownership
# changes, and no cgroup controllers (the feature's spec, QEMU configuration for a container).
configure_qemu() {
  log "writing the feature's block to ${QEMU_CONF}"
  write_block "${QEMU_CONF}" <<'EOF'
security_driver = "none"
user = "root"
group = "root"
dynamic_ownership = 0
remember_owner = 0
cgroup_controllers = [ ]
EOF
}

# Gives the read-write and read-only sockets of each daemon the feature starts to the libvirt group, without further
# authentication: no polkit runs in the container. The administration sockets keep the distribution's root-only mode.
configure_sockets() {
  local daemons daemon
  if [[ "${layout}" == monolithic ]]; then
    daemons=(libvirtd)
  else
    daemons=("${MODULAR_DAEMONS[@]}")
  fi
  for daemon in "${daemons[@]}"; do
    log "writing the feature's block to ${LIBVIRT_CONFIG_DIR}/${daemon}.conf"
    write_block "${LIBVIRT_CONFIG_DIR}/${daemon}.conf" <<EOF
unix_sock_group = "${LIBVIRT_GROUP}"
unix_sock_rw_perms = "0770"
unix_sock_ro_perms = "0770"
auth_unix_rw = "none"
auth_unix_ro = "none"
EOF
  done
}

# Leaves the default network defined and removes the mark that makes libvirt start it by itself, which only some
# distributions set; the entrypoint starts the network when the option defaultNetwork says so.
unmark_default_network() {
  if [[ -e "${DEFAULT_NETWORK_AUTOSTART}" || -L "${DEFAULT_NETWORK_AUTOSTART}" ]]; then
    log "removing the autostart mark ${DEFAULT_NETWORK_AUTOSTART}"
    rm --force "${DEFAULT_NETWORK_AUTOSTART}"
  fi
}

# Fails, before anything changes, when the remote user the Dev Container tooling names does not exist in the image.
check_remote_user() {
  id "${REMOTE_USER_NAME}" >/dev/null 2>&1 \
    || fail "the remote user \"${REMOTE_USER_NAME}\" does not exist in the image; create the user before this feature"
}

# Adds the remote user to the libvirt group, which the daemons' sockets belong to.
grant_remote_user() {
  if ! getent group "${LIBVIRT_GROUP}" >/dev/null; then
    log "creating the group ${LIBVIRT_GROUP}, which the packages did not create"
    groupadd --system "${LIBVIRT_GROUP}"
  fi
  if [[ "${REMOTE_USER_NAME}" == root ]]; then
    log "the remote user is root, which needs no group"
    return
  fi
  log "adding the remote user \"${REMOTE_USER_NAME}\" to the group ${LIBVIRT_GROUP}"
  usermod --append --groups "${LIBVIRT_GROUP}" "${REMOTE_USER_NAME}"
}

# Writes the settings start.sh reads at every start, and installs the two start scripts.
install_start_scripts() {
  mkdir --parents "${SHARE_DIR}"
  log "recording defaultNetwork=${DEFAULTNETWORK} and the layout ${layout} in ${SETTINGS_FILE}"
  printf 'defaultNetwork=%s\nlayout=%s\nremoteUser=%s\n' "${DEFAULTNETWORK}" "${layout}" "${REMOTE_USER_NAME}" \
    >"${SETTINGS_FILE}"
  chmod 0644 "${SETTINGS_FILE}"
  log "installing the entrypoint to ${START_SCRIPT} and the start check to ${CHECK_SCRIPT}"
  install --mode 0755 "${script_dir}/scripts/start.sh" "${START_SCRIPT}"
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
  check_remote_user
  install_packages
  detect_layout
  configure_qemu
  configure_sockets
  unmark_default_network
  grant_remote_user
  install_start_scripts
  clean_caches
  log "done"
}

main "$@"
