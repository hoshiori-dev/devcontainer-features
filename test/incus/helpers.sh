# shellcheck shell=bash
# Assertions shared by the incus tests. Sourced by test.sh, duplicate.sh, and the scenario scripts after
# dev-container-features-test-lib; each function returns non-zero on failure.

# The scripts that source this file use the constants it does not use itself.
# shellcheck disable=SC2034
readonly INCUS_START="/usr/local/share/incus-feature/start.sh"
# shellcheck disable=SC2034
readonly INCUS_CHECK="/usr/local/share/incus-feature/check.sh"
# shellcheck disable=SC2034
readonly INCUS_SETTINGS="/usr/local/share/incus-feature/settings"
readonly INCUS_RECORD="/run/incus-feature/status"
readonly INCUS_PID_FILE="/run/incus-feature/incusd.pid"
readonly INCUS_SOURCES="/etc/apt/sources.list.d/zabbly-incus.sources"
readonly INCUS_KEY="/etc/apt/keyrings/zabbly.asc"
readonly INCUS_IMAGE="feature-test"
readonly INCUS_INSTANCE="feature-test"

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
  sed -n "s/^$1=//p" "${INCUS_RECORD}"
}

# The daemon runs: the process ID file, whose first field is the process ID, names a process called incusd.
daemon_runs() {
  local pid
  pid="$(cut -d ' ' -f 1 "${INCUS_PID_FILE}")" || return
  [[ "$(cat "/proc/${pid}/comm")" == incusd ]]
}

# The container is privileged: PID 1 holds CAP_SYS_ADMIN (bit 21) and CAP_SYS_MODULE (bit 16), which Docker grants
# only to a privileged container.
container_is_privileged() {
  local caps
  caps="$(sed -n 's/^CapEff:[[:space:]]*//p' /proc/1/status)"
  (((16#${caps} >> 21) & 1)) && (((16#${caps} >> 16) & 1))
}

# The container's first process is an init that collects ended processes: Docker's, which the feature requests.
container_has_init() {
  [[ "$(cat /proc/1/comm)" =~ ^(docker-init|tini)$ ]]
}

# No ended incusd process waits to be collected: no process named incusd is in state Z, the third field of its
# stat file. The minimal images have no ps.
no_ended_daemon_process() {
  local stat_file stat
  for stat_file in /proc/[0-9]*/stat; do
    stat="$(cat "${stat_file}" 2>/dev/null)" || continue
    if [[ "${stat}" == *"(incusd) Z "* ]]; then
      printf '  uncollected: %s\n' "${stat%% *}"
      return 1
    fi
  done
}

# The repository definition names channel $1, the image's codename as its suite, and the pinned key file, and no
# other channel.
sources_name_channel() {
  local codename
  # shellcheck source=/dev/null
  codename="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME}")"
  grep -q -x "URIs: https://pkgs.zabbly.com/incus/$1" "${INCUS_SOURCES}" \
    && grep -q -x "Suites: ${codename}" "${INCUS_SOURCES}" \
    && grep -q -x "Signed-By: ${INCUS_KEY}" "${INCUS_SOURCES}" \
    && test "$(grep -c '^URIs:' "${INCUS_SOURCES}")" = 1
}

# The package $1 is installed in a Zabbly build: epoch 1 and the distribution tag Zabbly puts in its versions
# (1:7.6-debian13-202611072130), which no Debian or Ubuntu package of that name carries.
zabbly_package_installed() {
  local version
  version="$(dpkg-query -W -f='${Version}' "$1")" || return
  [[ "${version}" =~ ^1:[0-9.]+-(debian|ubuntu)[0-9.]+-[0-9]+$ ]]
}

# The package $1 is not installed.
package_absent() {
  ! dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

# The daemon holds at least one storage pool.
has_storage_pool() {
  [[ -n "$(incus storage list --format csv)" ]]
}

# The daemon holds at least one network it manages.
has_managed_network() {
  incus network list --format csv --columns nm | grep -q ',YES$'
}

# Builds a container image from a static BusyBox and imports it under the alias INCUS_IMAGE, so that no test depends
# on an image server. The instance's init asks the bridge's DHCP server for an address and then sleeps. BusyBox comes
# from the image's own repositories.
import_test_image() {
  local work arch
  if incus image info "${INCUS_IMAGE}" >/dev/null 2>&1; then return 0; fi
  if [[ ! -x /bin/busybox ]]; then
    as_root apt-get update >/dev/null || return
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends busybox-static \
      >/dev/null || return
  fi
  work="$(mktemp -d)"
  mkdir -p "${work}/rootfs/bin" "${work}/rootfs/sbin" "${work}/rootfs/etc" "${work}/rootfs/dev" \
    "${work}/rootfs/proc" "${work}/rootfs/sys" "${work}/rootfs/tmp"
  cp /bin/busybox "${work}/rootfs/bin/busybox"
  cat >"${work}/rootfs/etc/udhcpc.script" <<'EOF'
#!/bin/busybox sh
case "$1" in
  bound | renew) /bin/busybox ifconfig "${interface}" "${ip}" netmask "${subnet}" ;;
esac
EOF
  cat >"${work}/rootfs/sbin/init" <<'EOF'
#!/bin/busybox sh
/bin/busybox ifconfig eth0 up
/bin/busybox udhcpc -i eth0 -s /etc/udhcpc.script -n -q -t 20
exec /bin/busybox sleep 86400
EOF
  chmod +x "${work}/rootfs/etc/udhcpc.script" "${work}/rootfs/sbin/init"
  arch="$(uname -m)"
  printf 'architecture: %s\ncreation_date: 1\nproperties:\n  description: incus feature test image\n  os: busybox\n' \
    "${arch}" >"${work}/metadata.yaml"
  tar -C "${work}" --owner=0 --group=0 -czf "${work}/image.tar.gz" metadata.yaml rootfs || return
  incus image import "${work}/image.tar.gz" --alias "${INCUS_IMAGE}" || return
  rm -rf "${work}"
}

# An instance of the test image starts and gets an IPv4 address on the managed bridge within 60 seconds.
instance_starts_with_address() {
  local waited addresses
  import_test_image || return
  # incus launch reads an instance configuration from standard input when that is not a terminal.
  incus launch "${INCUS_IMAGE}" "${INCUS_INSTANCE}" </dev/null || return
  for ((waited = 0; waited < 60; waited++)); do
    addresses="$(incus list "${INCUS_INSTANCE}" --format csv --columns s4)"
    if [[ "${addresses}" == RUNNING,*"(eth0)"* ]]; then return 0; fi
    sleep 1
  done
  printf '  state and addresses after 60 seconds: %s\n' "${addresses}"
  incus info "${INCUS_INSTANCE}" --show-log || true
  return 1
}

# The running test instance has no memory controller, and a memory limit is refused or has no effect on it
# (the feature's spec, Instance limits are not applied).
instance_limit_not_applied() {
  if incus exec "${INCUS_INSTANCE}" -- /bin/busybox test -e /sys/fs/cgroup/memory.max; then return 1; fi
  if incus config set "${INCUS_INSTANCE}" limits.memory=64MiB 2>/dev/null; then
    ! incus exec "${INCUS_INSTANCE}" -- /bin/busybox test -e /sys/fs/cgroup/memory.max
  fi
}

# The test instance is stopped and removed.
remove_instance() {
  incus delete --force "${INCUS_INSTANCE}"
}

# Neither the remote user's home nor root's holds a GnuPG directory: the install checks its key in a temporary one.
no_gnupg_home() {
  [[ ! -e "${HOME}/.gnupg" ]] && ! as_root test -e /root/.gnupg
}

# The user running the test is root or a member of the incus-admin group.
root_or_admin_member() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then return 0; fi
  id -nG | tr ' ' '\n' | grep -q -x incus-admin
}

# A user who is neither root nor a member of incus-admin is refused by the daemon's socket. The user nobody runs the
# client with its configuration in a directory of its own.
outsider_is_refused() {
  local conf output
  local status=0
  conf="$(mktemp -d)"
  chmod 0777 "${conf}"
  output="$(as_root env INCUS_CONF="${conf}" setpriv --reuid nobody --regid nogroup --clear-groups incus list 2>&1)" \
    || status=$?
  printf '%s\n' "${output}" | tail -n 3
  as_root rm -rf "${conf:?}"
  ((status != 0)) && grep -q -i 'permission' <<<"${output}"
}
