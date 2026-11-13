#!/usr/bin/env bash
# Reports whether the libvirt daemons of the current container start run: the postStartCommand of the
# libvirt-in-docker feature, run as the remote user without privilege. It waits at most 90 seconds for the record
# start.sh writes to /run/libvirt-in-docker/status, takes a record of an earlier start for a missing one, and runs
# `virsh --connect qemu:///system version`. It exits zero with a one-line summary when the record reports started
# daemons and the command succeeds, and non-zero with the reason and the daemons' log directory otherwise. It changes
# nothing and takes no options.
set -euo pipefail

readonly RECORD_FILE="/run/libvirt-in-docker/status"
readonly LOG_DIR="/var/log/libvirt"
readonly SYSTEM_URI="qemu:///system"
readonly WAIT_SECONDS=90
readonly CONNECT_SECONDS=20

# virsh prints the untranslated text this script reads.
export LC_ALL="C"

log() {
  printf 'libvirt-in-docker: %s\n' "$*"
}

fail() {
  printf 'libvirt-in-docker: error: %s\n' "$*" >&2
  exit 1
}

# Prints the value of the first "$1=value" line of the start record, and nothing when the record or the line is
# missing.
field() {
  local line
  if [[ ! -r "${RECORD_FILE}" ]]; then return 0; fi
  while IFS= read -r line; do
    if [[ "${line}" == "$1="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <"${RECORD_FILE}"
}

# Prints the start time of PID 1, field 22 of /proc/1/stat, as start.sh records it.
start_time() {
  local stat fields
  stat="$(</proc/1/stat)"
  read -ra fields <<<"${stat##*) }"
  printf '%s\n' "${fields[19]}"
}

# Waits until the start record belongs to the current start: the entrypoint may still be running, and a record an
# earlier start left counts as missing.
wait_for_record() {
  local start recorded waited owner
  # The entrypoint runs as the user of PID 1 and starts nothing unless that user is root.
  owner="$(stat --format '%u' /proc/1)"
  if [[ "${owner}" != 0 ]]; then
    fail "the container's user is not root (UID ${owner}), so the feature's entrypoint started no daemon; run the" \
      "container as root and name the developer's user in remoteUser"
  fi
  start="$(start_time)"
  for ((waited = 0; waited < WAIT_SECONDS; waited++)); do
    recorded="$(field start)"
    if [[ "${recorded}" == "${start}" ]]; then return 0; fi
    sleep 1
  done
  fail "${RECORD_FILE} holds no record of the current start after ${WAIT_SECONDS} seconds, so the daemons were not" \
    "started: the feature's entrypoint must run as root; see the container log and ${LOG_DIR}"
}

main() {
  local result reason output version user kvm kvm_text network
  wait_for_record
  result="$(field result)"
  reason="$(field reason)"
  if [[ "${result}" != started ]]; then
    fail "the libvirt daemons are not running (${result:-no result recorded}): ${reason}; logs: ${LOG_DIR};" \
      "record: ${RECORD_FILE}"
  fi
  if ! output="$(timeout "${CONNECT_SECONDS}" virsh --connect "${SYSTEM_URI}" version --daemon 2>&1)"; then
    printf '%s\n' "${output}" >&2
    user="$(id --user --name)"
    fail "cannot connect to ${SYSTEM_URI} as ${user}, although the start record reports started daemons; a user" \
      "other than root must be a member of the libvirt group; logs: ${LOG_DIR}; record: ${RECORD_FILE}"
  fi
  version="$(sed --quiet 's/^Running against daemon: //p' <<<"${output}")"
  kvm="$(field kvm)"
  network="$(field defaultNetwork)"
  if [[ "${kvm}" == available ]]; then
    kvm_text="KVM is available"
  else
    kvm_text="KVM is not available, so guests run under software emulation"
  fi
  log "libvirt ${version:-of unknown version} answers at ${SYSTEM_URI}; ${kvm_text}; network default: ${network};" \
    "record: ${RECORD_FILE}"
}

main "$@"
