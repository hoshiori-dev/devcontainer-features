# shellcheck shell=bash
# Assertions shared by the libvirt-outside-of-docker tests. Sourced by test.sh, duplicate.sh, and the scenario scripts
# after dev-container-features-test-lib; each function returns non-zero on failure.

readonly LOD_ALIGN="/usr/local/share/libvirt-outside-of-docker/align_group.sh"
readonly LOD_CHECK="/usr/local/share/libvirt-outside-of-docker/check.sh"
readonly LOD_SETTINGS="/usr/local/share/libvirt-outside-of-docker/settings"
readonly LOD_RECORD="/run/libvirt-outside-of-docker/status"

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
  sed -n "s/^$1=//p" "${LOD_RECORD}"
}

# No libvirt daemon and no QEMU system emulator is installed.
no_daemon_installed() {
  local name
  for name in libvirtd virtqemud; do
    if command -v "${name}" >/dev/null 2>&1 || [[ -e "/usr/sbin/${name}" ]]; then return 1; fi
  done
  ! compgen -G '/usr/bin/qemu-system-*' >/dev/null
}

# The start check exits zero and says that no host socket is mounted, naming the mount to add.
check_reports_no_socket() {
  local output
  output="$("${LOD_CHECK}" 2>&1)" || return
  grep -q 'no host socket is mounted' <<<"${output}" \
    && grep -q 'source=/run/libvirt,target=/run/libvirt,type=bind,readonly' <<<"${output}"
}

# The checks that run inside `bash -c` strings call this function and read these paths, so they are exported.
export -f record_field
export LOD_ALIGN LOD_CHECK LOD_RECORD LOD_SETTINGS
