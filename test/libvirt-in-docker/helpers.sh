# shellcheck shell=bash
# Assertions shared by the libvirt-in-docker tests. Sourced by test.sh, duplicate.sh, and the scenario scripts after
# dev-container-features-test-lib; each function returns non-zero on failure.

readonly LID_START="/usr/local/share/libvirt-in-docker/start.sh"
readonly LID_CHECK="/usr/local/share/libvirt-in-docker/check.sh"
readonly LID_RECORD="/run/libvirt-in-docker/status"
readonly LID_BLOCK_BEGIN="# BEGIN libvirt-in-docker feature: this block is replaced at each install of the feature"
readonly LID_GUEST="feature-test"

# Runs a command as root: the tests run as the image's remote user, which may be a sudoer.
as_root() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

# Runs the installer of this checkout as root with only the given NAME=value options in its environment; prints its
# output and returns its status.
run_installer() {
  as_root env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root "$@" \
    bash "$(dirname "$0")/_feature/install.sh" 2>&1
}

# Prints the value of the line "$1=value" of the start record.
record_field() {
  sed -n "s/^$1=//p" "${LID_RECORD}"
}

# The daemon $1 runs: its process ID file names a process of that name.
daemon_runs() {
  local pid
  pid="$(as_root cat "/run/$1.pid")" || return
  [[ "$(cat "/proc/${pid}/comm")" == "$1" ]]
}

# The daemons of the layout the start record names run, with virtlogd.
layout_daemons_run() {
  local layout name
  layout="$(record_field layout)"
  case "${layout}" in
    monolithic) daemon_runs libvirtd || return ;;
    modular)
      for name in virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtnwfilterd; do
        daemon_runs "${name}" || return
      done
      ;;
    *) return 1 ;;
  esac
  daemon_runs virtlogd
}

# The QEMU system emulator of the container's architecture is installed.
native_emulator_installed() {
  case "$(uname -m)" in
    x86_64) command -v qemu-system-x86_64 ;;
    aarch64) command -v qemu-system-aarch64 ;;
    *) return 1 ;;
  esac
}

# A UEFI firmware image is installed where the distributions put it.
firmware_installed() {
  compgen -G '/usr/share/OVMF/*.fd' || compgen -G '/usr/share/AAVMF/*.fd' || compgen -G '/usr/share/edk2/*/*.fd'
}

# The container is privileged: PID 1 holds CAP_SYS_ADMIN, bit 21 of its effective capabilities.
container_is_privileged() {
  local caps
  caps="$(sed -n 's/^CapEff:[[:space:]]*//p' /proc/1/status)"
  (((16#${caps} >> 21) & 1))
}

# The directory $1 is a mount.
is_mount() {
  grep -q " $1 " /proc/self/mounts
}

# Prints the value of the line "$1:" of `virsh net-info default`, such as Active or Autostart. The output is read
# whole first: a grep that stops at its first match would end virsh with a broken pipe.
network_info() {
  local info
  info="$(virsh net-info default)" || return
  sed -n "s/^$1: *//p" <<<"${info}"
}

network_is_active() {
  [[ "$(network_info Active)" == yes ]]
}

network_is_defined_and_inactive() {
  [[ "$(network_info Active)" == no ]]
}

# swtpm is not installed, except where the distribution's QEMU driver package depends on it, as Fedora's does.
swtpm_absent_unless_required() {
  if ! command -v swtpm >/dev/null; then return 0; fi
  command -v rpm >/dev/null && rpm --query --whatrequires swtpm-tools | grep -q '^libvirt-daemon-driver-qemu'
}

# swtpm and its setup tool are installed. Only swtpm's status is read: swtpm_setup --version of swtpm 0.7, which
# Debian and Ubuntu ship, prints the version and exits 1.
swtpm_installed() {
  swtpm --version && command -v swtpm_setup
}

# Defines and starts a guest of the container's architecture under software emulation, so no check depends on KVM,
# with virt-install: an empty 1 GiB disk image in libvirt's default pool, "imported" as if it held a system, on the
# network $1 ("network=default", or "none"). Succeeds when libvirt lists the guest as running.
start_emulated_guest() {
  virt-install --name "${LID_GUEST}" --memory 128 --vcpus 1 --virt-type qemu --import --disk size=1 \
    --network "$1" --graphics none --osinfo generic --noautoconsole || return
  [[ "$(virsh domstate "${LID_GUEST}")" == running ]]
}

# Stops the guest and removes its definition, its firmware variables, and its disk image.
remove_guest() {
  virsh destroy "${LID_GUEST}" || true
  virsh undefine "${LID_GUEST}" --nvram --remove-all-storage \
    || virsh undefine "${LID_GUEST}" --remove-all-storage
}

# The file $1 holds the feature's block exactly once.
block_once() {
  local count
  count="$(as_root grep -c -x -F "${LID_BLOCK_BEGIN}" "$1")" || return
  [[ "${count}" == 1 ]]
}

# The feature's block is the first thing in the file $1, where libvirt gives its settings precedence.
block_first() {
  [[ "$(as_root head -n 1 "$1")" == "${LID_BLOCK_BEGIN}" ]]
}

# The configuration file of each daemon of the layout the start record names holds the feature's block once.
daemon_blocks_once() {
  local name
  local names=(libvirtd)
  if [[ "$(record_field layout)" == modular ]]; then
    names=(virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtnwfilterd)
  fi
  for name in "${names[@]}"; do
    block_once "/etc/libvirt/${name}.conf" || return
  done
}

# The checks that run inside `bash -c` strings call these functions and read these paths, so they are exported.
export -f as_root record_field daemon_runs layout_daemons_run block_first block_once
export LID_BLOCK_BEGIN
export LID_START LID_CHECK LID_RECORD LID_GUEST
