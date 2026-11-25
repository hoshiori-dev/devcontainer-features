#!/usr/bin/env bash
# Reports whether the Incus daemon of the current container start runs: the postStartCommand of the incus feature,
# run as the remote user without privilege. It waits at most 240 seconds for the record start.sh writes to
# /run/incus-feature/status, takes a record of an earlier start for a missing one, and asks the daemon for its
# server information through the socket. It exits zero with a one-line summary when the record reports a started
# daemon and the daemon answers, and non-zero with the reason and the daemon's log otherwise. A failed first
# initialization is printed and does not fail the check. It changes nothing and takes no options; the incus client
# it runs keeps its configuration in a temporary directory that is removed at the end.
set -euo pipefail

readonly RECORD_FILE="/run/incus-feature/status"
readonly START_SCRIPT="/usr/local/share/incus-feature/start.sh"
readonly LOG_FILE="/var/log/incus/incusd.log"
# Longer than the entrypoint's own limits add up to: WAIT_SECONDS, INIT_SECONDS, and twice QUERY_SECONDS of start.sh.
readonly WAIT_SECONDS=240
readonly CONNECT_SECONDS=20

# incus prints the untranslated text this script shows.
export LC_ALL="C"

client_dir=""

log() {
  printf 'incus: %s\n' "$*"
}

fail() {
  printf 'incus: error: %s\n' "$*" >&2
  exit 1
}

# Removes the client's temporary configuration directory on every exit.
cleanup() {
  if [[ -n "${client_dir}" ]]; then rm --recursive --force "${client_dir}"; fi
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
# earlier start left counts as missing. When no record of this start exists and PID 1 is not root's, it does not
# wait: the entrypoint runs as the container's user and starts nothing unless that user is root.
wait_for_record() {
  local start recorded waited owner
  start="$(start_time)"
  owner="$(stat --format '%u' /proc/1)"
  for ((waited = 0; waited < WAIT_SECONDS; waited++)); do
    recorded="$(field start)"
    if [[ "${recorded}" == "${start}" ]]; then return 0; fi
    if [[ "${owner}" != 0 ]]; then
      fail "${RECORD_FILE} holds no record of the current start, and the container's process 1 is not root's (UID" \
        "${owner}), so the feature's entrypoint started no daemon; run the container as root and name the" \
        "developer's user in remoteUser, or run sudo ${START_SCRIPT}"
    fi
    sleep 1
  done
  fail "${RECORD_FILE} holds no record of the current start after ${WAIT_SECONDS} seconds, so the daemon was not" \
    "started: the feature's entrypoint must run as root; see the container log and ${LOG_FILE}"
}

main() {
  local result reason initialization output version user
  wait_for_record
  result="$(field result)"
  reason="$(field reason)"
  if [[ "${result}" != started ]]; then
    fail "the Incus daemon is not running (${result:-no result recorded}): ${reason}; log: ${LOG_FILE};" \
      "record: ${RECORD_FILE}"
  fi
  trap cleanup EXIT
  client_dir="$(mktemp --directory)"
  export INCUS_CONF="${client_dir}"
  if ! output="$(timeout "${CONNECT_SECONDS}" incus query /1.0 2>&1)"; then
    printf '%s\n' "${output}" >&2
    # A user ID without a name in the container is reported by its number.
    user="$(id --user --name 2>/dev/null)" || user="$(id --user)"
    fail "cannot reach the Incus daemon as ${user}, although the start record reports a started daemon; a user" \
      "other than root must be a member of the incus-admin group; log: ${LOG_FILE}; record: ${RECORD_FILE}"
  fi
  version="$(incus --version)"
  initialization="$(field initialization)"
  if [[ "${initialization}" == failed:* ]]; then
    log "error: the first initialization ${initialization}; run incus admin init yourself"
  fi
  log "Incus ${version} answers; initialization: ${initialization}; record: ${RECORD_FILE}"
}

main "$@"
