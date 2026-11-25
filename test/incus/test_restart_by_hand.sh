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
  cut -d ' ' -f 1 "${INCUS_PID_FILE}"
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
# INITIALIZE=none in the environment would record "not requested" if the script read it; the image says minimal.
check "The daemon has stopped: the script exits zero, with another initialize in its environment" \
  as_root env INITIALIZE=none "${INCUS_START}"
check "The daemon has stopped: another daemon process runs" another_daemon_process "${pid_before}"
check "The daemon has stopped: the daemon answers the remote user" incus list
check "Environment does not change the start: the record reports a started daemon and the image's initialize" \
  test "$(record_field result):$(record_field initialization)" \
  = "started:skipped: the daemon holds a storage pool or a managed network"
check "The daemon has stopped: the instance is still listed" incus info "${INCUS_INSTANCE}"
check "the instance is removed" remove_instance

# A failed first initialization in the record: the start check still exits zero and prints the failure.
check_reports_failed_initialization() {
  local output
  local status=0
  as_root cp "${INCUS_RECORD}" "${INCUS_RECORD}.saved"
  sed 's/^initialization=.*/initialization=failed: incus admin init --minimal: stand-in failure/' \
    "${INCUS_RECORD}.saved" | as_root tee "${INCUS_RECORD}" >/dev/null
  output="$("${INCUS_CHECK}" 2>&1)" || status=$?
  as_root mv "${INCUS_RECORD}.saved" "${INCUS_RECORD}"
  printf '%s\n' "${output}"
  ((status == 0)) || return
  grep -q 'the first initialization failed: incus admin init --minimal: stand-in failure' <<<"${output}"
}
check "Failed initialization: the start check exits zero and prints the failure" check_reports_failed_initialization

# Puts the script given on standard input in the place of the package's daemon script.
replace_daemon_script() {
  as_root tee "${DAEMON_SCRIPT}" >/dev/null
  as_root chmod +x "${DAEMON_SCRIPT}"
}

# The record reports a failed start whose reason matches the pattern $1.
failed_with_reason() {
  [[ "$(record_field result)" == failed ]] && grep -q -E "^reason=$1" "${INCUS_RECORD}"
}

check "the daemon ends once more" stop_daemon
as_root mv "${DAEMON_SCRIPT}" "${DAEMON_SCRIPT}.saved"

# No daemon script at all.
check "Daemon fails to start, no daemon script: the script still exits zero" as_root "${INCUS_START}"
check "Daemon fails to start, no daemon script: the record names the missing script" \
  failed_with_reason "${DAEMON_SCRIPT}, which the Zabbly package installs, is missing"

# A daemon script that fails at once.
printf '#!/bin/sh\necho "stand-in: the daemon cannot start" >&2\nexit 1\n' | replace_daemon_script
check "Daemon fails to start, the daemon ends: the script still exits zero" as_root "${INCUS_START}"
check "Daemon fails to start, the daemon ends: the record names the failure" \
  failed_with_reason 'incusd was started and does not keep running'
check "Not started: the start check exits non-zero with the reason and the log" check_fails_with_reason

# A daemon script that keeps running and never answers: the script gives up after its limit of 60 seconds.
printf '#!/bin/sh\nwhile :; do sleep 1; done\n' | replace_daemon_script
check "Daemon fails to start, no answer: the script still exits zero" as_root "${INCUS_START}"
check "Daemon fails to start, no answer: the record names the limit" \
  failed_with_reason 'incusd runs but did not answer within 60 seconds'
as_root kill "$(daemon_pid)"
as_root mv "${DAEMON_SCRIPT}.saved" "${DAEMON_SCRIPT}"

check "with the package's script back, the script starts the daemon" as_root "${INCUS_START}"
check "the start check exits zero again" "${INCUS_CHECK}"

reportResults
