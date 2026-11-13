#!/usr/bin/env bash
# Starts the libvirt daemons: the entrypoint of the libvirt-in-docker feature, run as root at every container start
# before the container's command. It reads the settings install.sh stored in
# /usr/local/share/libvirt-in-docker/settings and nothing from its environment or its arguments. In order: it stops
# when /run/libvirt is a mount point or the daemon already answers; stops daemons that run without answering;
# removes the runtime state an earlier start of this container left under /run (libvirt's sockets, process ID files,
# and record of what it started), which the start record of that start identifies; starts
# virtlogd and then libvirtd or, on a distribution without it, the modular daemons; waits at most 30 seconds for
# qemu:///system to answer; and, with defaultNetwork true, starts the network "default" when it is defined and not
# active. The outcome goes to the start record /run/libvirt-in-docker/status, which check.sh reports. It always exits
# zero, so the container's command runs whatever happened.
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

# The tools this script runs come from the system directories, whatever PATH the container was given.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# The settings of the image: whether to start the default network, and the daemon layout.
default_network=""
layout=""
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

# Ends the script with the result $1 (started, failed, or refused) and the reason $2 in the record.
finish() {
  step="writing the start record"
  reason="$2"
  result="$1"
  write_record
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
    monolithic) daemons=("${MONOLITHIC_DAEMONS[@]}") ;;
    modular) daemons=("${MODULAR_DAEMONS[@]}") ;;
    *) finish failed "${SETTINGS_FILE} names no known daemon layout (\"${layout}\"); rebuild the container" ;;
  esac
}

# Succeeds when the system daemon answers within 5 seconds.
daemon_answers() {
  timeout 5 virsh --connect "${SYSTEM_URI}" version >/dev/null 2>&1
}

# Stops the daemon $1 when its process ID file names a running process of that name, and waits until it is gone.
stop_daemon() {
  local name="$1"
  local pid_file="${PID_DIR}/${name}.pid"
  local pid comm
  [[ -r "${pid_file}" ]] || return 0
  pid="$(<"${pid_file}")"
  [[ "${pid}" =~ ^[0-9]+$ && -r "/proc/${pid}/comm" ]] || return 0
  comm="$(<"/proc/${pid}/comm")"
  [[ "${comm}" == "${name}" ]] || return 0
  log "stopping a ${name} (process ${pid}) that no longer answers"
  kill "${pid}"
  for _ in {1..50}; do
    [[ -e "/proc/${pid}" ]] || return 0
    sleep 0.1
  done
}

# Prints the start time the start record names, and nothing when there is no record.
recorded_start() {
  local line
  if [[ ! -r "${RECORD_FILE}" ]]; then return 0; fi
  while IFS= read -r line; do
    if [[ "${line}" == start=* ]]; then
      printf '%s\n' "${line#start=}"
      return 0
    fi
  done <"${RECORD_FILE}"
}

# Stops daemons that still run but do not answer, and removes what an earlier start of the container left under
# /run. A restarted container keeps /run, and libvirt would take the leftovers for its own state: it would not start
# a network it believes started already. State of the current start is kept, so that daemons started again by hand
# find their guests and networks; the start record tells the two apart.
remove_earlier_state() {
  local name recorded current
  step="stopping daemons that do not answer"
  for name in "${daemons[@]}" "${LOG_DAEMON}"; do
    stop_daemon "${name}"
    rm --force "${PID_DIR}/${name}.pid"
  done
  step="removing the runtime state of an earlier start"
  recorded="$(recorded_start)"
  current="$(start_time)"
  if [[ "${recorded}" == "${current}" ]]; then
    log "keeping ${LIBVIRT_RUN_DIR}, which this start of the container wrote"
    return 0
  fi
  if [[ -e "${LIBVIRT_RUN_DIR}" ]]; then
    log "removing ${LIBVIRT_RUN_DIR}, the runtime state of an earlier start"
    rm --recursive --force "${LIBVIRT_RUN_DIR}"
  fi
}

start_daemons() {
  local name waited
  for name in "${LOG_DAEMON}" "${daemons[@]}"; do
    step="starting ${name}"
    log "starting ${name}"
    "${name}" --daemon
  done
  step="waiting for ${SYSTEM_URI} to answer"
  for ((waited = 0; waited < WAIT_SECONDS; waited++)); do
    if daemon_answers; then return 0; fi
    sleep 1
  done
  finish failed "${SYSTEM_URI} did not answer within ${WAIT_SECONDS} seconds of starting ${daemons[*]}; see ${LOG_DIR}"
}

# Sets kvm to "available" when /dev/kvm can be opened for reading and writing, and to "unavailable" otherwise.
detect_kvm() {
  step="looking at ${KVM_DEVICE}"
  kvm="unavailable"
  if [[ -c "${KVM_DEVICE}" ]] && (: <>"${KVM_DEVICE}") 2>/dev/null; then kvm="available"; fi
}

# Sets network to the state of the default network, after starting it when defaultNetwork is true and it is defined
# and not active. A network that is not defined or does not start is recorded and stops nothing.
apply_default_network() {
  local info output
  step="looking at the network ${DEFAULT_NETWORK}"
  if ! info="$(virsh --connect "${SYSTEM_URI}" net-info "${DEFAULT_NETWORK}" 2>&1)"; then
    network="not defined"
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
  if output="$(virsh --connect "${SYSTEM_URI}" net-start "${DEFAULT_NETWORK}" 2>&1)"; then
    network="active"
  else
    network="failed to start: ${output//$'\n'/ }"
    log "error: the network ${DEFAULT_NETWORK} did not start: ${output}"
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
  if mountpoint --quiet "${LIBVIRT_RUN_DIR}"; then
    finish refused "${LIBVIRT_RUN_DIR} is a mount point, and a daemon started there would write into another system's libvirt directory; remove the mount from devcontainer.json"
  fi
  if daemon_answers; then
    # A run by hand while the daemon answers: nothing is removed, restarted, or recorded anew.
    result="started"
    log "${SYSTEM_URI} already answers: nothing is changed"
    exit 0
  fi
  remove_earlier_state
  start_daemons
  detect_kvm
  apply_default_network
  finish started "${daemons[*]} and ${LOG_DAEMON} run and ${SYSTEM_URI} answers"
}

main "$@"
