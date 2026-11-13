#!/usr/bin/env bash
# Reports whether the libvirt client reaches the host's daemon: the postStartCommand of the libvirt-outside-of-docker
# feature, run as the remote user without privilege. When neither /run/libvirt/virtqemud-sock nor
# /run/libvirt/libvirt-sock is a socket, it says that no host socket is mounted, names the mount to add, and exits
# zero. Otherwise it waits at most 30 seconds for the record align_group.sh writes for the current start, runs
# `virsh --connect qemu:///system version`, and exits zero with a one-line summary, or non-zero with virsh's error
# and the start record. When the entrypoint added the user to a group only after this script had started, it runs
# virsh through `sg`, with that group, as a process started later would have it. It changes nothing and takes no
# options.
set -euo pipefail

readonly RECORD_FILE="/run/libvirt-outside-of-docker/status"
readonly SOCKET_PATHS=("/run/libvirt/virtqemud-sock" "/run/libvirt/libvirt-sock")
readonly SYSTEM_URI="qemu:///system"
readonly MOUNT_LINE='"mounts": ["source=/run/libvirt,target=/run/libvirt,type=bind,readonly"]'
readonly WAIT_SECONDS=30
readonly CONNECT_SECONDS=20
# What `sg` runs; it holds no value from outside this script.
readonly VERSION_COMMAND="virsh --connect qemu:///system version --daemon"

# virsh prints the untranslated text this script reads.
export LC_ALL="C"

socket=""

log() {
  printf 'libvirt-outside-of-docker: %s\n' "$*"
}

fail() {
  printf 'libvirt-outside-of-docker: error: %s\n' "$*" >&2
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

# Prints the start time of PID 1, field 22 of /proc/1/stat, as align_group.sh records it.
start_time() {
  local stat fields
  stat="$(</proc/1/stat)"
  read -ra fields <<<"${stat##*) }"
  printf '%s\n' "${fields[19]}"
}

find_socket() {
  local path
  for path in "${SOCKET_PATHS[@]}"; do
    if [[ -S "${path}" ]]; then
      socket="${path}"
      return 0
    fi
  done
}

# Waits until the start record belongs to the current start: the entrypoint may still be running, and a record an
# earlier start left counts as missing. Returns non-zero when none appears. When no record of this start exists and
# PID 1 is not root's, it does not wait: the entrypoint runs as the container's user and records nothing unless that
# user is root.
wait_for_record() {
  local start recorded waited owner
  start="$(start_time)"
  owner="$(stat --format '%u' /proc/1)"
  for ((waited = 0; waited < WAIT_SECONDS; waited++)); do
    recorded="$(field start)"
    if [[ "${recorded}" == "${start}" ]]; then return 0; fi
    if [[ "${owner}" != 0 ]]; then return 1; fi
    sleep 1
  done
  return 1
}

# Prints what the start record says about the group alignment, or that this start has no record.
alignment_summary() {
  local result reason
  if ! wait_for_record; then
    printf '%s\n' "${RECORD_FILE} holds no record of this start, so the entrypoint did not run as root or did not" \
      "finish within ${WAIT_SECONDS} seconds, and no group was aligned"
    return 0
  fi
  result="$(field result)"
  reason="$(field reason)"
  printf '%s\n' "group alignment at this start: ${result}: ${reason} (record: ${RECORD_FILE})"
}

# Succeeds when the start record names a group that the user has in the group database but this process, which
# started before the entrypoint added the user, does not.
group_added_after_start() {
  local group="$1"
  local mine database
  [[ -n "${group}" ]] || return 1
  mine="$(id --groups --name)"
  database="$(id --groups --name "$(id --user --name)")"
  [[ " ${mine} " != *" ${group} "* && " ${database} " == *" ${group} "* ]]
}

main() {
  local alignment output version user uid group
  local late=""
  local connected=false
  find_socket
  if [[ -z "${socket}" ]]; then
    log "no host socket is mounted at ${SOCKET_PATHS[0]} or ${SOCKET_PATHS[1]};" \
      "to manage the host's virtual machines, add to devcontainer.json: ${MOUNT_LINE}"
    exit 0
  fi
  alignment="$(alignment_summary)"
  alignment="${alignment//$'\n'/ }"
  group="$(field group)"
  if group_added_after_start "${group}" && command -v sg >/dev/null 2>&1; then
    late=" (as a member of ${group}, which this process, started before the group alignment, does not have yet)"
    if output="$(timeout "${CONNECT_SECONDS}" sg "${group}" -c "${VERSION_COMMAND}" 2>&1)"; then
      connected=true
    fi
  elif output="$(timeout "${CONNECT_SECONDS}" virsh --connect "${SYSTEM_URI}" version --daemon 2>&1)"; then
    connected=true
  fi
  if [[ "${connected}" != true ]]; then
    printf '%s\n' "${output}" >&2
    if [[ -r "${RECORD_FILE}" ]]; then
      printf '%s\n' "start record ${RECORD_FILE}:" >&2
      cat "${RECORD_FILE}" >&2
    fi
    user="$(id --user --name)"
    uid="$(id --user)"
    fail "cannot connect to ${SYSTEM_URI} through ${socket} as ${user} (UID ${uid}); ${alignment};" \
      "check that the host's libvirt daemon runs and lets this user in"
  fi
  version="$(sed --quiet 's/^Running against daemon: //p' <<<"${output}")"
  log "connected to the host's libvirt daemon ${version:-of unknown version} at ${SYSTEM_URI} through" \
    "${socket}${late}"
}

main "$@"
