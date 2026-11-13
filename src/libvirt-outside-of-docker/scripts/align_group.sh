#!/usr/bin/env bash
# Gives the remote user access to a mounted host libvirt socket: the entrypoint of the libvirt-outside-of-docker
# feature, run at every container start before the container's command. When it runs as root, it looks at the first
# of /run/libvirt/libvirt-sock and /run/libvirt/virtqemud-sock that is a socket and adds the remote user, whose name
# install.sh stored in /usr/local/share/libvirt-outside-of-docker/settings, to a group of the container that has the
# socket's GID; when no group has it, the group libvirt-host gets it. It changes nothing for a socket that every
# user may write to or that belongs to GID 0, and it never writes under /run/libvirt. The outcome goes to the start
# record /run/libvirt-outside-of-docker/status, which check.sh reports. It always exits zero, so the container's
# command runs whatever happened. It takes no option from its environment or its arguments.
set -euo pipefail

readonly SETTINGS_FILE="/usr/local/share/libvirt-outside-of-docker/settings"
readonly RUN_DIR="/run/libvirt-outside-of-docker"
readonly RECORD_FILE="/run/libvirt-outside-of-docker/status"
readonly RECORD_TMP_FILE="/run/libvirt-outside-of-docker/status.tmp"
# The sockets of the host's system daemon, in the order they are looked at: the monolithic daemon's (which
# virtproxyd also provides), then the modular QEMU daemon's.
readonly SOCKET_PATHS=("/run/libvirt/libvirt-sock" "/run/libvirt/virtqemud-sock")
# The group that takes the socket's GID when no group of the container has it.
readonly HOST_GROUP="libvirt-host"

# The tools this script runs come from the system directories, whatever PATH the container was given.
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

remote_user=""
socket=""
socket_gid=""
socket_mode=""
# What the record says: the result (aligned, unchanged, or failed), why, and the group the user was added to.
result=""
reason=""
group=""
# The step under way, which a failure is recorded with.
step="starting"

log() {
  printf 'libvirt-outside-of-docker: %s\n' "$*"
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
    printf 'remoteUser=%s\n' "${remote_user}"
    printf 'socket=%s\n' "${socket}"
    printf 'socketGid=%s\n' "${socket_gid}"
    printf 'socketMode=%s\n' "${socket_mode}"
    printf 'group=%s\n' "${group}"
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
    reason="the entrypoint stopped while ${step}"
    log "error: ${reason}"
    write_record || true
  fi
  exit 0
}

# Ends the script with the result $1 and the reason $2 in the record.
finish() {
  step="writing the start record"
  reason="$2"
  result="$1"
  write_record || log "error: cannot write the start record ${RECORD_FILE}, so the start check will report no record"
  log "${result}: ${reason}"
  exit 0
}

read_remote_user() {
  local line
  step="reading ${SETTINGS_FILE}"
  while IFS= read -r line; do
    if [[ "${line}" == remoteUser=* ]]; then remote_user="${line#remoteUser=}"; fi
  done <"${SETTINGS_FILE}"
}

# Sets socket, socket_gid, and socket_mode from the first path that is a socket; leaves them empty when none is.
find_socket() {
  local path
  step="looking for the host's socket"
  for path in "${SOCKET_PATHS[@]}"; do
    if [[ -S "${path}" ]]; then
      socket="${path}"
      socket_gid="$(stat --format '%g' "${path}")"
      socket_mode="$(stat --format '%a' "${path}")"
      return 0
    fi
  done
}

# Adds the remote user to the group ${group} unless the user is a member already.
add_remote_user() {
  local groups
  step="adding ${remote_user} to the group ${group}"
  groups="$(id --groups --name "${remote_user}")"
  if [[ " ${groups} " == *" ${group} "* ]]; then return 0; fi
  usermod --append --groups "${group}" "${remote_user}"
}

# Makes the remote user a member of a group with the socket's GID: the group that has it, or libvirt-host, which is
# created or renumbered to it. No other group's GID changes.
align() {
  local entry
  step="looking up the group with GID ${socket_gid}"
  # getent exits 2 when no group has the GID.
  entry="$(getent group "${socket_gid}" || true)"
  if [[ -n "${entry}" ]]; then
    group="${entry%%:*}"
    add_remote_user
    finish aligned "${remote_user} is a member of the existing group ${group} (GID ${socket_gid}) of ${socket}"
  fi
  group="${HOST_GROUP}"
  if getent group "${HOST_GROUP}" >/dev/null; then
    step="giving the group ${HOST_GROUP} the GID ${socket_gid}"
    groupmod --gid "${socket_gid}" "${HOST_GROUP}"
  else
    step="creating the group ${HOST_GROUP} with the GID ${socket_gid}"
    groupadd --gid "${socket_gid}" "${HOST_GROUP}"
  fi
  add_remote_user
  finish aligned "${remote_user} is a member of ${HOST_GROUP} (GID ${socket_gid}) of ${socket}"
}

main() {
  local uid
  # Every file this script writes is readable by every user and writable by root alone.
  umask 022
  uid="$(id --user)"
  if ((uid != 0)); then
    log "the entrypoint does not run as root (UID ${uid}): no group is changed and no start record is written"
    exit 0
  fi
  trap handle_exit EXIT
  read_remote_user
  find_socket
  if [[ -z "${socket}" ]]; then
    finish unchanged "no host socket is mounted at ${SOCKET_PATHS[0]} or ${SOCKET_PATHS[1]}"
  fi
  if [[ -z "${remote_user}" || "${remote_user}" == root ]]; then
    finish unchanged "the remote user is root, which needs no group"
  fi
  if ! id "${remote_user}" >/dev/null 2>&1; then
    finish unchanged "the remote user \"${remote_user}\" recorded at build time does not exist in the container"
  fi
  # The last octal digit of the mode holds the permissions of every other user; 2 is write.
  if (((8#${socket_mode} & 2) != 0)); then
    finish unchanged "${socket} is writable by every user (mode ${socket_mode}); the host decides who may connect"
  fi
  if [[ "${socket_gid}" == 0 ]]; then
    finish unchanged "the group of ${socket} is root (GID 0), and the remote user is never added to the root group"
  fi
  align
}

main "$@"
