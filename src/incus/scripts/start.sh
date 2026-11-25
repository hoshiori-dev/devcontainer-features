#!/usr/bin/env bash
# Starts the Incus daemon: the entrypoint of the incus feature, run as root at every container start before the
# container's command. It reads the settings install.sh stored in /usr/local/share/incus-feature/settings and
# nothing from its environment or its arguments. In order: it stops when the daemon answers and the record of this
# start says so; starts the daemon when it does not run, through the script the Zabbly systemd unit runs
# (/opt/incus/lib/systemd/incusd), with the group incus-admin for its socket and /var/log/incus/incusd.log as its
# log; waits at most 60 seconds until the daemon answers; and, with initialize minimal, runs
# `incus admin init --minimal` when the daemon holds no storage pool and no managed network. It never stops the
# daemon and writes nothing into /var/lib/incus itself. The outcome goes to the start record
# /run/incus-feature/status, which check.sh reports. It always exits zero, so the container's command runs whatever
# happened.
set -euo pipefail

readonly SETTINGS_FILE="/usr/local/share/incus-feature/settings"
readonly RUN_DIR="/run/incus-feature"
readonly RECORD_FILE="/run/incus-feature/status"
readonly RECORD_TMP_FILE="/run/incus-feature/status.tmp"
# The process ID of the daemon this script started, and the start time of the container start it belongs to.
readonly PID_FILE="/run/incus-feature/incusd.pid"
# Where root's incus client, run by this script, keeps its configuration, so that nothing is written to /root.
readonly CLIENT_DIR="/run/incus-feature/client"
# What the incus client printed to standard error in the last query of the daemon's state.
readonly QUERY_ERROR_FILE="/run/incus-feature/query.err"
# The script the Zabbly systemd unit runs: it sets the paths of the bundle under /opt/incus and runs the daemon.
readonly DAEMON_SCRIPT="/opt/incus/lib/systemd/incusd"
readonly DAEMON_NAME="incusd"
readonly ADMIN_GROUP="incus-admin"
readonly LOG_DIR="/var/log/incus"
readonly LOG_FILE="/var/log/incus/incusd.log"
# What the daemon prints before it opens its log.
readonly OUTPUT_FILE="/var/log/incus/incusd.out"
readonly WAIT_SECONDS=60
# The limit of the first initialization and of each query of the daemon's state.
readonly INIT_SECONDS=120
readonly QUERY_SECONDS=20

# The tools this script runs come from the system directories, whatever PATH the container was given, and incus
# prints the untranslated text this script reads.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL="C"
export INCUS_CONF="${CLIENT_DIR}"

# The settings of the image.
initialize=""
remote_user=""
# What the record says.
result=""
reason=""
initialization=""
# The step under way, which a failure is recorded with.
step="starting"

log() {
  printf 'incus: %s\n' "$*"
}

# Prints the start time of PID 1, field 22 of /proc/1/stat, which tells this start of the container from an earlier
# one. The command name, field 2, stands in parentheses and may hold spaces, so the fields are counted after it.
start_time() {
  local stat fields
  stat="$(</proc/1/stat)"
  read -ra fields <<<"${stat##*) }"
  printf '%s\n' "${fields[19]}"
}

# Writes the start record, readable by every user and writable by root alone, replacing an earlier one at once.
# Each command returns on failure by itself: the callers handle a failed write, which switches `set -e` off in here.
write_record() {
  local start
  start="$(start_time)" || return
  mkdir --parents "${RUN_DIR}" || return
  {
    printf 'start=%s\n' "${start}"
    printf 'result=%s\n' "${result}"
    printf 'reason=%s\n' "${reason}"
    printf 'initialization=%s\n' "${initialization}"
    printf 'remoteUser=%s\n' "${remote_user}"
    printf 'log=%s\n' "${LOG_FILE}"
  } >"${RECORD_TMP_FILE}" || return
  mv --force "${RECORD_TMP_FILE}" "${RECORD_FILE}"
}

# Runs on every exit: a step that failed is recorded as a failed start, and the script still exits zero, so the
# container's command runs.
# The EXIT trap calls this function, which shellcheck cannot see.
# shellcheck disable=SC2317
handle_exit() {
  if [[ -z "${result}" ]]; then
    result="failed"
    reason="the entrypoint stopped while ${step}; see the container log and ${LOG_DIR}"
    log "error: ${reason}"
    write_record || true
  fi
  exit 0
}

# Ends the script with the result $1 (started or failed) and, as the reason in the record, the remaining arguments
# joined by spaces.
finish() {
  step="writing the start record"
  reason="${*:2}"
  result="$1"
  write_record || log "error: cannot write the start record ${RECORD_FILE}, so the start check will report no record"
  log "${result}: ${reason}"
  exit 0
}

read_settings() {
  local line
  step="reading ${SETTINGS_FILE}"
  while IFS= read -r line; do
    case "${line}" in
      initialize=*) initialize="${line#initialize=}" ;;
      remoteUser=*) remote_user="${line#remoteUser=}" ;;
    esac
  done <"${SETTINGS_FILE}"
  case "${initialize}" in
    minimal | none) ;;
    *) finish failed "${SETTINGS_FILE} names no known value of initialize (\"${initialize}\"); rebuild the container" ;;
  esac
}

# Prints the value of the first "$1=value" line of the start record, and nothing when the record or the line is
# missing.
recorded() {
  local line
  if [[ ! -r "${RECORD_FILE}" ]]; then return 0; fi
  while IFS= read -r line; do
    if [[ "${line}" == "$1="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <"${RECORD_FILE}"
}

# Succeeds when the start record belongs to the current start of the container and reports a started daemon.
recorded_as_started() {
  local start recorded_result current
  start="$(recorded start)"
  recorded_result="$(recorded result)"
  current="$(start_time)"
  [[ "${start}" == "${current}" && "${recorded_result}" == started ]]
}

# Succeeds when the daemon answers on its socket within 5 seconds.
daemon_answers() {
  timeout 5 incus query /1.0 >/dev/null 2>&1
}

# Succeeds when the daemon this script started in the current start of the container runs: the process ID file holds
# the start time of this start and names a process of the daemon's name that has not ended. A restarted container
# keeps /run, and the number an earlier start wrote may by now belong to another process, so a file of an earlier
# start counts as none. A process that ended and that PID 1 has not collected (state Z) still has an entry in /proc;
# it does not count.
daemon_runs() {
  local pid start current comm stat fields
  [[ -r "${PID_FILE}" ]] || return 1
  read -r pid start <"${PID_FILE}" || return 1
  current="$(start_time)"
  [[ "${start}" == "${current}" ]] || return 1
  [[ "${pid}" =~ ^[0-9]+$ && -r "/proc/${pid}/comm" ]] || return 1
  # The process may end between the looks at /proc.
  comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
  [[ "${comm}" == "${DAEMON_NAME}" ]] || return 1
  stat="$(cat "/proc/${pid}/stat" 2>/dev/null || true)"
  # The state is field 3, the first after the command name in parentheses.
  read -ra fields <<<"${stat##*) }"
  [[ -n "${fields[0]:-}" && "${fields[0]}" != Z ]]
}

# Starts the daemon when it does not run, and waits until it answers. A daemon that runs is left alone, also when it
# does not answer yet.
start_daemon() {
  local deadline pid current
  # SECONDS counts the seconds since the script started; one attempt to connect may itself take up to 5.
  deadline=$((SECONDS + WAIT_SECONDS))
  if ! daemon_runs; then
    step="starting ${DAEMON_NAME}"
    [[ -x "${DAEMON_SCRIPT}" ]] \
      || finish failed "${DAEMON_SCRIPT}, which the Zabbly package installs, is missing or not executable; rebuild" \
        "the container"
    log "starting ${DAEMON_NAME} through ${DAEMON_SCRIPT}, with its log in ${LOG_FILE}"
    mkdir --parents "${RUN_DIR}" "${LOG_DIR}"
    # Deviation from shell-style.md (Commands): the command's name comes from a variable. It holds the readonly
    # path at the top of this file and nothing from outside the script.
    "${DAEMON_SCRIPT}" --group "${ADMIN_GROUP}" --logfile "${LOG_FILE}" </dev/null >"${OUTPUT_FILE}" 2>&1 &
    pid=$!
    current="$(start_time)"
    printf '%s %s\n' "${pid}" "${current}" >"${PID_FILE}"
  fi
  step="waiting for ${DAEMON_NAME} to answer"
  while ((SECONDS < deadline)); do
    if daemon_answers; then return 0; fi
    if ! daemon_runs; then
      finish failed "${DAEMON_NAME} was started and does not keep running; see ${LOG_FILE} and ${OUTPUT_FILE} for" \
        "why it ends"
    fi
    sleep 1
  done
  finish failed "${DAEMON_NAME} runs but did not answer within ${WAIT_SECONDS} seconds; see ${LOG_FILE}, and restart" \
    "the container if the daemon hangs"
}

# Sets initialization to what was done about the first initialization. With initialize minimal, a daemon that holds
# no storage pool and no managed network gets Incus's own minimal initialization; a daemon that holds either is left
# alone. A failure is recorded and stops nothing.
apply_initialization() {
  local pools networks errors output
  if [[ "${initialize}" != minimal ]]; then
    initialization="not requested (initialize is ${initialize})"
    return 0
  fi
  step="reading the daemon's storage pools and networks"
  # Only what the client prints to standard output is the list: a notice on standard error must not read as a pool.
  if ! pools="$(timeout "${QUERY_SECONDS}" incus storage list --format csv 2>"${QUERY_ERROR_FILE}")"; then
    errors="$(<"${QUERY_ERROR_FILE}")"
    initialization="failed: cannot list the storage pools: ${errors//$'\n'/ }"
    log "error: ${initialization}"
    return 0
  fi
  # The columns are the name and whether Incus manages the network; a managed one reads "name,YES".
  if ! networks="$(timeout "${QUERY_SECONDS}" incus network list --format csv --columns nm \
    2>"${QUERY_ERROR_FILE}")"; then
    errors="$(<"${QUERY_ERROR_FILE}")"
    initialization="failed: cannot list the networks: ${errors//$'\n'/ }"
    log "error: ${initialization}"
    return 0
  fi
  if [[ -n "${pools}" ]] || grep --quiet ',YES$' <<<"${networks}"; then
    initialization="skipped: the daemon holds a storage pool or a managed network"
    return 0
  fi
  step="running incus admin init --minimal"
  log "initializing the daemon with incus admin init --minimal"
  if output="$(timeout "${INIT_SECONDS}" incus admin init --minimal 2>&1)"; then
    initialization="done: incus admin init --minimal"
  else
    initialization="failed: incus admin init --minimal: ${output//$'\n'/ }"
    log "error: ${initialization}"
  fi
}

main() {
  local uid
  # Every file this script writes is readable by every user and writable by root alone.
  umask 022
  uid="$(id --user)"
  if ((uid != 0)); then
    log "the entrypoint does not run as root (UID ${uid}): no daemon is started and no start record is written"
    exit 0
  fi
  trap handle_exit EXIT
  read_settings
  step="creating ${RUN_DIR}"
  mkdir --parents "${RUN_DIR}" "${CLIENT_DIR}"
  if recorded_as_started && daemon_answers; then
    # A run by hand while the daemon answers and is recorded so: nothing is started, initialized, or recorded anew.
    result="started"
    log "${DAEMON_NAME} answers: nothing is changed"
    exit 0
  fi
  if ! daemon_answers; then start_daemon; fi
  apply_initialization
  finish started "${DAEMON_NAME} answers"
}

main "$@"
