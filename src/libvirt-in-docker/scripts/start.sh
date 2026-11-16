#!/usr/bin/env bash
# Starts the libvirt daemons: the entrypoint of the libvirt-in-docker feature, run as root at every container start
# before the container's command. It reads the settings install.sh stored in
# /usr/local/share/libvirt-in-docker/settings and nothing from its environment or its arguments. In order: it stops
# when /run/libvirt is a mount point or holds one, or when every daemon runs, qemu:///system answers, and the record
# of this start says so; removes the runtime state an earlier start of this container left under /run (libvirt's
# sockets, process ID files, and record of what it started), which the start record of that start identifies; starts
# each daemon that does not run: virtlogd, and libvirtd or, on a distribution without it, the modular daemons; waits
# at most 30 seconds until all of them run and qemu:///system answers; and, with defaultNetwork true, starts the
# network "default" when it is defined and not active. It never stops a daemon. The outcome goes to the start record
# /run/libvirt-in-docker/status, which check.sh reports. It always exits zero, so the container's command runs
# whatever happened.
set -euo pipefail

readonly SETTINGS_FILE="/usr/local/share/libvirt-in-docker/settings"
readonly RUN_DIR="/run/libvirt-in-docker"
readonly RECORD_FILE="/run/libvirt-in-docker/status"
readonly RECORD_TMP_FILE="/run/libvirt-in-docker/status.tmp"
# libvirt's runtime directory: sockets, guest process ID files, and the record of what libvirt started.
readonly LIBVIRT_RUN_DIR="/run/libvirt"
# Where each daemon writes its process ID file: /run/<daemon>.pid.
readonly PID_DIR="/run"
readonly LOG_DIR="/var/log/libvirt"
readonly SYSTEM_URI="qemu:///system"
readonly KVM_DEVICE="/dev/kvm"
readonly DEFAULT_NETWORK="default"
readonly LOG_DAEMON="virtlogd"
readonly MONOLITHIC_DAEMONS=(libvirtd)
readonly MODULAR_DAEMONS=(virtqemud virtnetworkd virtstoraged virtnodedevd virtsecretd virtnwfilterd)
readonly WAIT_SECONDS=30
# The limit of one virsh call that changes or reads a network.
readonly NETWORK_SECONDS=30

# The tools this script runs come from the system directories, whatever PATH the container was given, and virsh
# prints the untranslated text this script reads.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LC_ALL="C"

# The settings of the image: whether to start the default network, and the daemon layout.
default_network=""
layout=""
# Every daemon of the layout, the log daemon first.
daemons=()
# What the record says.
result=""
reason=""
kvm=""
network=""
# The step under way, which a failure is recorded with.
step="starting"

log() {
  printf 'libvirt-in-docker: %s\n' "$*"
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
write_record() {
  local start
  start="$(start_time)"
  mkdir --parents "${RUN_DIR}"
  {
    printf 'start=%s\n' "${start}"
    printf 'result=%s\n' "${result}"
    printf 'reason=%s\n' "${reason}"
    printf 'layout=%s\n' "${layout}"
    printf 'kvm=%s\n' "${kvm}"
    printf 'defaultNetwork=%s\n' "${network}"
    printf 'logs=%s\n' "${LOG_DIR}"
  } >"${RECORD_TMP_FILE}"
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

# Ends the script with the result $1 (started, failed, or refused) and, as the reason in the record, the remaining
# arguments joined by spaces.
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
      defaultNetwork=*) default_network="${line#defaultNetwork=}" ;;
      layout=*) layout="${line#layout=}" ;;
    esac
  done <"${SETTINGS_FILE}"
  case "${layout}" in
    monolithic) daemons=("${LOG_DAEMON}" "${MONOLITHIC_DAEMONS[@]}") ;;
    modular) daemons=("${LOG_DAEMON}" "${MODULAR_DAEMONS[@]}") ;;
    *) finish failed "${SETTINGS_FILE} names no known daemon layout (\"${layout}\"); rebuild the container" ;;
  esac
}

# Succeeds when the system daemon answers within 5 seconds.
daemon_answers() {
  timeout 5 virsh --connect "${SYSTEM_URI}" version >/dev/null 2>&1
}

# Succeeds when the daemon $1 runs: its process ID file names a process of that name that has not ended. A process
# that ended and that PID 1 has not collected (state Z) still has an entry in /proc; it does not count.
daemon_runs() {
  local name="$1"
  local pid_file="${PID_DIR}/${name}.pid"
  local pid comm stat fields
  [[ -r "${pid_file}" ]] || return 1
  pid="$(<"${pid_file}")"
  [[ "${pid}" =~ ^[0-9]+$ && -r "/proc/${pid}/comm" ]] || return 1
  # The process may end between the looks at /proc.
  comm="$(cat "/proc/${pid}/comm" 2>/dev/null || true)"
  [[ "${comm}" == "${name}" ]] || return 1
  stat="$(cat "/proc/${pid}/stat" 2>/dev/null || true)"
  # The state is field 3, the first after the command name in parentheses.
  read -ra fields <<<"${stat##*) }"
  [[ -n "${fields[0]:-}" && "${fields[0]}" != Z ]]
}

# Succeeds when every daemon of the layout runs.
all_daemons_run() {
  local name
  for name in "${daemons[@]}"; do
    daemon_runs "${name}" || return 1
  done
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

# Succeeds when the start record belongs to the current start of the container and reports started daemons.
recorded_as_started() {
  local start result current
  start="$(recorded start)"
  result="$(recorded result)"
  current="$(start_time)"
  [[ "${start}" == "${current}" && "${result}" == started ]]
}

# Removes what an earlier start of the container left under /run. A restarted container keeps /run, and libvirt
# would take the leftovers for its own state: it would not start a network it believes started already. State of
# the current start is kept, so that daemons started again by hand find their guests and networks; the start record
# tells the two apart. Nothing is removed while a daemon runs, whatever the record says.
remove_earlier_state() {
  local name recorded current
  step="removing the runtime state of an earlier start"
  recorded="$(recorded start)"
  current="$(start_time)"
  if [[ "${recorded}" == "${current}" ]]; then
    log "keeping ${LIBVIRT_RUN_DIR}, which this start of the container wrote"
    return 0
  fi
  for name in "${daemons[@]}"; do
    if daemon_runs "${name}"; then
      log "keeping ${LIBVIRT_RUN_DIR}, because ${name} runs"
      return 0
    fi
  done
  for name in "${daemons[@]}"; do
    rm --force "${PID_DIR}/${name}.pid"
  done
  if [[ -e "${LIBVIRT_RUN_DIR}" ]]; then
    log "removing ${LIBVIRT_RUN_DIR}, the runtime state of an earlier start"
    # Nothing mounted below the directory is entered: it would be another system's.
    rm --recursive --force --one-file-system "${LIBVIRT_RUN_DIR}"
  fi
}

# Starts each daemon of the layout that does not run, and waits until every daemon runs and the system daemon
# answers. A daemon that runs is left alone, also when it does not answer: guests and their logs depend on it. Check
# again during the wait, because a daemon that was already stopping can end after the first check.
start_daemons() {
  local name deadline
  local missing=()
  # SECONDS counts the seconds since the script started; one attempt may itself take up to 5.
  deadline=$((SECONDS + WAIT_SECONDS))
  while ((SECONDS < deadline)); do
    for name in "${daemons[@]}"; do
      if daemon_runs "${name}"; then continue; fi
      step="starting ${name}"
      log "starting ${name}"
      rm --force "${PID_DIR}/${name}.pid"
      # Deviation from shell-style.md (Commands): the command's name comes from a variable. It holds one of the
      # daemon names in the readonly lists at the top of this file and nothing from outside the script.
      "${name}" --daemon
    done
    step="waiting for ${daemons[*]} to run and ${SYSTEM_URI} to answer"
    if all_daemons_run && daemon_answers; then return 0; fi
    sleep 1
  done
  for name in "${daemons[@]}"; do
    if ! daemon_runs "${name}"; then missing+=("${name}"); fi
  done
  if ((${#missing[@]} > 0)); then
    finish failed "after ${WAIT_SECONDS} seconds ${missing[*]} still does not keep running, although it was started" \
      "again each second; see ${LOG_DIR} for why it ends"
  fi
  finish failed "${daemons[*]} run, but ${SYSTEM_URI} did not answer within ${WAIT_SECONDS} seconds; see ${LOG_DIR}," \
    "and restart the container if a daemon hangs"
}

# Sets kvm to "available" when /dev/kvm can be opened for reading and writing, and to "unavailable" otherwise.
detect_kvm() {
  step="looking at ${KVM_DEVICE}"
  kvm="unavailable"
  if [[ -c "${KVM_DEVICE}" ]] && (: <>"${KVM_DEVICE}") 2>/dev/null; then kvm="available"; fi
}

# Sets network to the state of the default network, after starting it when defaultNetwork is true and it is defined
# and not active. A network that is not defined, cannot be read, or does not start is recorded and stops nothing.
apply_default_network() {
  local info output
  local status=0
  step="looking at the network ${DEFAULT_NETWORK}"
  info="$(timeout "${NETWORK_SECONDS}" virsh --connect "${SYSTEM_URI}" net-info "${DEFAULT_NETWORK}" 2>&1)" || status=$?
  if ((status != 0)); then
    # libvirt's message for a network it does not know; every other failure is reported as it is. timeout exits
    # 124 when it ends a call that printed nothing.
    if [[ "${info}" == *"Network not found"* ]]; then
      network="not defined"
    else
      if ((status == 124)); then info="no answer within ${NETWORK_SECONDS} seconds"; fi
      network="unknown: ${info//$'\n'/ }"
      log "error: cannot read the state of the network ${DEFAULT_NETWORK}: ${info}"
    fi
    return 0
  fi
  if grep --quiet '^Active: *yes' <<<"${info}"; then
    network="active"
    return 0
  fi
  if [[ "${default_network}" != true ]]; then
    network="inactive (defaultNetwork is false)"
    return 0
  fi
  step="starting the network ${DEFAULT_NETWORK}"
  log "starting the network ${DEFAULT_NETWORK}"
  if output="$(timeout "${NETWORK_SECONDS}" virsh --connect "${SYSTEM_URI}" net-start "${DEFAULT_NETWORK}" 2>&1)"; then
    network="active"
  else
    network="failed to start: ${output//$'\n'/ }"
    log "error: the network ${DEFAULT_NETWORK} did not start: ${output}"
  fi
}

# Prints the first mount point that is the directory $1 or lies below it, and nothing when there is none. The mount
# points of this container are the fifth field of each line of /proc/self/mountinfo, with symbolic links resolved,
# so the directory is compared both as it is written and as it resolves: in an image where /run is a link, a mount
# at /run/libvirt is listed under the link's target.
mount_at_or_below() {
  local directory="$1"
  local resolved fields path
  resolved="$(realpath --canonicalize-missing "${directory}")" || return 1
  while read -ra fields; do
    for path in "${directory}" "${resolved}"; do
      if [[ "${fields[4]}" == "${path}" || "${fields[4]}" == "${path}/"* ]]; then
        printf '%s\n' "${fields[4]}"
        return 0
      fi
    done
  done </proc/self/mountinfo
}

main() {
  local uid mount_point
  # Every file this script writes is readable by every user and writable by root alone.
  umask 022
  uid="$(id --user)"
  if ((uid != 0)); then
    log "the entrypoint does not run as root (UID ${uid}): no daemon is started and no start record is written"
    exit 0
  fi
  trap handle_exit EXIT
  read_settings
  step="reading the mount points of the container"
  mount_point="$(mount_at_or_below "${LIBVIRT_RUN_DIR}")"
  if [[ -n "${mount_point}" ]]; then
    finish refused "${mount_point} is a mount point, and a daemon started in ${LIBVIRT_RUN_DIR} would write into" \
      "another system's libvirt directory; remove the mount from devcontainer.json"
  fi
  if recorded_as_started && all_daemons_run && daemon_answers; then
    # A run by hand while everything runs and is recorded so: nothing is removed, started, or recorded anew.
    result="started"
    log "${daemons[*]} run and ${SYSTEM_URI} answers: nothing is changed"
    exit 0
  fi
  remove_earlier_state
  start_daemons
  detect_kvm
  apply_default_network
  finish started "${daemons[*]} run and ${SYSTEM_URI} answers"
}

main "$@"
