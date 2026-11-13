#!/usr/bin/env bash
# Scenario "test_restart_by_hand": libvirt-in-docker with default options on the Ubuntu image, as the remote user
# vscode. The script runs the entrypoint's script again as root in five states of the container and asserts what the
# spec says of each: while the daemon answers ("Run again by hand", "Environment does not change the start"), with a
# daemon binary that fails ("Daemon fails to start", "Daemon not started"), with a file system mounted at
# /run/libvirt ("Mounted run directory"), with one daemon stopped ("A daemon has stopped"), and over the state an
# earlier start left ("State of an earlier start").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly DAEMON="/usr/sbin/libvirtd"

daemon_pid() {
  as_root cat /run/libvirtd.pid
}

# Stops libvirtd and waits until its process is gone.
stop_daemon() {
  local pid
  pid="$(daemon_pid)"
  as_root kill "${pid}"
  for _ in $(seq 1 50); do
    [[ -e "/proc/${pid}" ]] || return 0
    sleep 0.1
  done
  return 1
}

log_daemon_pid() {
  as_root cat /run/virtlogd.pid
}

# Stops virtlogd and waits until its process is gone.
stop_log_daemon() {
  local pid
  pid="$(log_daemon_pid)"
  as_root kill "${pid}"
  for _ in $(seq 1 50); do
    [[ -e "/proc/${pid}" ]] || return 0
    sleep 0.1
  done
  return 1
}

check_fails_naming() {
  local output
  if output="$("${LID_CHECK}" 2>&1)"; then return 1; fi
  printf '%s\n' "${output}"
  grep -q -- "$1" <<<"${output}"
}

check "the layout is monolithic" test "$(record_field layout)" = monolithic
check "a software-emulated guest on the network default reaches the running state" start_emulated_guest network=default

pid_before="$(daemon_pid)"
record_before="$(cat "${LID_RECORD}")"
check "Run again by hand: the script exits zero, also with an option's name in its environment" \
  as_root env DEFAULTNETWORK=false "${LID_START}"
check "Run again by hand: no daemon was restarted" test "$(daemon_pid)" = "${pid_before}"
check "Run again by hand: the guest keeps running" test "$(virsh domstate "${LID_GUEST}")" = running
check "Run again by hand: the start record is unchanged" test "$(cat "${LID_RECORD}")" = "${record_before}"
check "Environment does not change the start: the network default is still active" network_is_active

as_root useradd --create-home outsider
check "User outside the group: the connection is refused" \
  bash -c '! sudo runuser -u outsider -- virsh --connect qemu:///system list --all'
check "the administration socket is root-only" \
  test "$(as_root stat -c '%U %a' /run/libvirt/libvirt-admin-sock)" = "root 700"
check "the guest is removed" remove_guest

# A daemon binary that fails: the real one is put aside for one run.
log_pid_before="$(log_daemon_pid)"
check "the daemon stops" stop_daemon
as_root mv "${DAEMON}" "${DAEMON}.real"
printf '#!/bin/sh\necho "libvirtd: stand-in that fails" >&2\nexit 1\n' | as_root tee "${DAEMON}" >/dev/null
as_root chmod 0755 "${DAEMON}"
check "Daemon fails to start: the script still exits zero" as_root "${LID_START}"
as_root mv "${DAEMON}.real" "${DAEMON}"
check "Daemon fails to start: the start record names the failure" \
  bash -c "test \"\$(record_field result)\" = failed && record_field reason | grep -q 'while starting libvirtd'"
check "Daemon not started: the start check exits non-zero and names the log directory" \
  check_fails_naming '/var/log/libvirt'

# A file system mounted at /run/libvirt, as a mount of another system's directory would be.
as_root mkdir -p /run/libvirt
as_root mount -t tmpfs tmpfs /run/libvirt
check "Mounted run directory: the script exits zero" as_root "${LID_START}"
check "Mounted run directory: the start record says the start was refused" test "$(record_field result)" = refused
check "Mounted run directory: nothing was created under the mount" \
  test -z "$(as_root find /run/libvirt -mindepth 1)"
check "Mounted run directory: no daemon was started" bash -c '! test -e /run/libvirtd.pid'
check "Mounted run directory: the start check exits non-zero and names the mount" \
  check_fails_naming 'remove the mount from devcontainer.json'
as_root umount /run/libvirt

# One daemon has stopped: it is started, and the daemon that ran is left alone, with libvirt's runtime state.
check "A daemon has stopped: the script exits zero" as_root "${LID_START}"
check "A daemon has stopped: the daemons run again" test "$(record_field result)" = started
check "A daemon has stopped: virtlogd, which ran, kept its process" test "$(log_daemon_pid)" = "${log_pid_before}"
check "A daemon has stopped: the network default is still active" network_is_active

# The state an earlier start left, as a restarted container keeps it: libvirt's runtime directory with a leftover
# file, a start record of another start, and no daemon running. A restart also gives the container a new network
# namespace, so the network's bridge is removed first.
check "the network default stops" virsh net-destroy default
check "the daemon stops" stop_daemon
check "virtlogd stops" stop_log_daemon
as_root touch /run/libvirt/left-by-an-earlier-start
as_root sed -i 's/^start=.*/start=0/' "${LID_RECORD}"
check "State of an earlier start: the script exits zero" as_root "${LID_START}"
check "State of an earlier start: the leftover is gone" bash -c '! test -e /run/libvirt/left-by-an-earlier-start'
check "State of an earlier start: the daemons run again" test "$(record_field result)" = started
check "State of an earlier start: the network default is active again" network_is_active
check "the start check exits zero" "${LID_CHECK}"

# A start recorded as failed although the daemons answer by now, as after a slow start.
as_root sed -i 's/^result=.*/result=failed/' "${LID_RECORD}"
check "Record of a failed start: the script exits zero" as_root "${LID_START}"
check "Record of a failed start: the record reports started daemons" test "$(record_field result)" = started
check "Record of a failed start: the start check exits zero" "${LID_CHECK}"

reportResults
