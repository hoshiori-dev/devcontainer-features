#!/usr/bin/env bash
# Scenario "test_restart_by_hand": incus installed on the Ubuntu 24.04 dev container image with default options, for
# the remote user vscode. Root runs the entrypoint's script again: while the daemon runs with a running instance,
# nothing changes, whatever the environment says ("Run again by hand", "Environment does not change the start");
# after the daemon has stopped, it is started again ("The daemon has stopped"); and with a daemon script that fails,
# the script still exits zero, the record names the failure, and the start check fails with it ("Daemon fails to
# start", "Not started").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly DAEMON_SCRIPT="/opt/incus/lib/systemd/incusd"

# Prints the process ID of the daemon the entrypoint started.
daemon_pid() {
  cat "${INCUS_PID_FILE}"
}

# Ends the daemon and waits until its process is gone. The instances' own processes outlive it.
stop_daemon() {
  local pid waited
  pid="$(daemon_pid)"
  as_root kill "${pid}"
  for ((waited = 0; waited < 60; waited++)); do
    if [[ ! -e "/proc/${pid}" ]]; then return 0; fi
    sleep 1
  done
  return 1
}

# The daemon runs, in a process other than $1.
another_daemon_process() {
  daemon_runs && [[ "$(daemon_pid)" != "$1" ]]
}

# The test instance is in the state $1.
instance_state_is() {
  [[ "$(incus list "${INCUS_INSTANCE}" --format csv --columns s)" == "$1" ]]
}

# The start check exits non-zero and prints the recorded reason and the daemon's log.
check_fails_with_reason() {
  local output
  local status=0
  output="$("${INCUS_CHECK}" 2>&1)" || status=$?
  printf '%s\n' "${output}"
  ((status != 0)) || return
  grep -q 'does not keep running' <<<"${output}" && grep -q '/var/log/incus/incusd.log' <<<"${output}"
}

check "an instance starts and gets an address on the managed bridge" instance_starts_with_address

pid_before="$(daemon_pid)"
record_before="$(cat "${INCUS_RECORD}")"
check "Run again by hand: the script exits zero with options of another meaning in its environment" \
  as_root env INITIALIZE=none CHANNEL=lts-6.0 VM=true "${INCUS_START}"
check "Run again by hand: the daemon was not restarted" test "$(daemon_pid)" = "${pid_before}"
check "Run again by hand: the start record is unchanged" test "$(cat "${INCUS_RECORD}")" = "${record_before}"
check "Run again by hand: the instance keeps running" instance_state_is RUNNING

check "The daemon has stopped: the daemon ends" stop_daemon
check "The daemon has stopped: the script exits zero" as_root "${INCUS_START}"
check "The daemon has stopped: another daemon process runs" another_daemon_process "${pid_before}"
check "The daemon has stopped: the daemon answers the remote user" incus list
check "The daemon has stopped: the record reports a started daemon that was initialized before" \
  test "$(record_field result):$(record_field initialization)" \
  = "started:skipped: the daemon holds a storage pool or a managed network"
check "The daemon has stopped: the instance is still listed" incus info "${INCUS_INSTANCE}"
check "the instance is removed" remove_instance

# A daemon script that fails at once stands in for the package's.
check "the daemon ends once more" stop_daemon
as_root mv "${DAEMON_SCRIPT}" "${DAEMON_SCRIPT}.saved"
printf '#!/bin/sh\necho "stand-in: the daemon cannot start" >&2\nexit 1\n' | as_root tee "${DAEMON_SCRIPT}" >/dev/null
as_root chmod +x "${DAEMON_SCRIPT}"
check "Daemon fails to start: the script still exits zero" as_root "${INCUS_START}"
check "Daemon fails to start: the record reports a failed start" test "$(record_field result)" = failed
check "Daemon fails to start: the record names the failure" \
  bash -c "grep -q '^reason=incusd was started and does not keep running' ${INCUS_RECORD}"
check "Not started: the start check exits non-zero with the reason and the log" check_fails_with_reason
as_root mv "${DAEMON_SCRIPT}.saved" "${DAEMON_SCRIPT}"

check "with the package's script back, the script starts the daemon" as_root "${INCUS_START}"
check "the start check exits zero again" "${INCUS_CHECK}"

reportResults
