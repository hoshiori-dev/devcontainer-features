#!/usr/bin/env bash
# Checks the Pi project state once per container creation, as the remote user: the /var/lib/pi mount, the link from
# the effective agent directory ~/.pi/agent, ownership, private permissions, and access. A detected ownership or
# permission mismatch reruns this script as root through noninteractive sudo (--repair UID GID), which repairs only
# inside the mount and never follows symlinks out of it.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/pi"
readonly AGENT_DIR="${STATE_DIR}/agent"
readonly SELF_PATH="/usr/local/share/pi-feature/initialize"
# Relative to the agent directory: the files in which Pi stores provider and MCP credentials.
readonly CREDENTIAL_FILES=(auth.json mcp-auth.json)

log() {
  printf 'pi: %s\n' "$*"
}

fail() {
  printf 'pi: error: %s\n' "$*" >&2
  exit 1
}

# Fails unless the feature's volume is mounted at /var/lib/pi.
check_mount() {
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume"
  fi
}

# Fails when PI_CODING_AGENT_DIR points Pi at another directory or HOME is unusable; changes nothing.
check_environment() {
  # Pi ignores an empty value, so only a non-empty one points it elsewhere.
  [[ -z "${PI_CODING_AGENT_DIR:-}" ]] \
    || fail "PI_CODING_AGENT_DIR is set; remove it so Pi keeps its state in ${AGENT_DIR} through ~/.pi/agent"
  [[ "${HOME:-}" == /* && -d "${HOME}" ]] || fail "the remote user's HOME is unavailable; fix HOME and retry"
}

# Root-only repair: $1 and $2 are the remote user's numeric UID and GID, passed through noninteractive sudo.
repair_state() {
  local uid="$1" gid="$2" file
  [[ "$(id --user)" == 0 && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
    || fail "invalid repair request; rerun ${SELF_PATH} without arguments as the remote user"
  check_mount
  if [[ -L "${AGENT_DIR}" || ( -e "${AGENT_DIR}" && ! -d "${AGENT_DIR}" ) ]]; then
    fail "${AGENT_DIR} is not a directory; preserve it and resolve it manually"
  fi
  # On directories GNU chmod keeps set-user-ID and set-group-ID under a mode with one leading zero; 00700 clears them,
  # so a repaired directory has exactly the mode state_is_healthy expects.
  if [[ "$(stat --format=%u "${STATE_DIR}")" != "${uid}" ]] \
    || [[ -d "${AGENT_DIR}" && "$(stat --format=%u "${AGENT_DIR}")" != "${uid}" ]]; then
    log "repairing ownership inside ${STATE_DIR} for UID ${uid}"
    find -P "${STATE_DIR}" -xdev -exec chown --no-dereference "${uid}:${gid}" -- {} +
    find -P "${STATE_DIR}" -xdev -type d -exec chmod 00700 -- {} +
    find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
  fi
  chmod 00700 "${STATE_DIR}"
  if [[ ! -e "${AGENT_DIR}" ]]; then
    install --directory --mode 0700 --owner "${uid}" --group "${gid}" "${AGENT_DIR}"
  fi
  chmod 00700 "${AGENT_DIR}"
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -f "${AGENT_DIR}/${file}" && ! -L "${AGENT_DIR}/${file}" ]]; then
      chown "${uid}:${gid}" "${AGENT_DIR}/${file}"
      chmod 0600 "${AGENT_DIR}/${file}"
    fi
  done
}

# Fails unless the effective agent path ~/.pi/agent is missing or links to the volume, ~/.pi lies outside the volume,
# and the link target is not something other than a directory; changes nothing.
check_link() {
  local parent="${HOME%/}/.pi" canonical
  canonical="$(readlink --canonicalize-missing "${parent}")"
  [[ "${canonical}" != "${STATE_DIR}" && "${canonical}" != "${STATE_DIR}"/* ]] \
    || fail "${parent} lies inside ${STATE_DIR}; use a home outside the state volume"
  if [[ -L "${parent}/agent" ]]; then
    [[ "$(readlink "${parent}/agent")" == "${AGENT_DIR}" ]] \
      || fail "${parent}/agent links elsewhere; preserve it and resolve the mapping manually"
  elif [[ -e "${parent}/agent" ]]; then
    fail "${parent}/agent already exists; back it up and migrate it explicitly before using this feature"
  elif [[ ( -e "${parent}" || -L "${parent}" ) && ! -d "${parent}" ]]; then
    fail "${parent} is not a directory; move it aside and rerun ${SELF_PATH}"
  fi
  if [[ -L "${AGENT_DIR}" || ( -e "${AGENT_DIR}" && ! -d "${AGENT_DIR}" ) ]]; then
    fail "${AGENT_DIR} is not a directory; preserve it and resolve it manually"
  fi
}

# Succeeds when the state root, the agent directory, and the credential files have the remote user's private modes. A
# credential file that is a symlink belongs to a store the user chose and is not followed.
state_is_healthy() {
  local uid="$1" file
  [[ "$(stat --format=%u:%a "${STATE_DIR}")" == "${uid}:700" ]] || return 1
  [[ -d "${AGENT_DIR}" && ! -L "${AGENT_DIR}" ]] || return 1
  [[ "$(stat --format=%u:%a "${AGENT_DIR}")" == "${uid}:700" ]] || return 1
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -f "${AGENT_DIR}/${file}" && ! -L "${AGENT_DIR}/${file}" ]]; then
      [[ "$(stat --format=%u:%a "${AGENT_DIR}/${file}")" == "${uid}:600" ]] || return 1
    fi
  done
}

# Proves that the remote user can create and remove a file in the agent directory.
check_access() {
  local probe
  probe="$(mktemp "${AGENT_DIR}/.pi-feature-check.XXXXXX")" \
    || fail "${AGENT_DIR} is not writable; repair the volume permissions and rerun ${SELF_PATH}"
  rm -- "${probe}"
}

create_link() {
  local parent="${HOME%/}/.pi"
  if [[ ! -L "${parent}/agent" ]]; then
    log "linking ${parent}/agent to ${AGENT_DIR}"
    mkdir --parents "${parent}"
    ln --symbolic --no-target-directory "${AGENT_DIR}" "${parent}/agent"
  fi
}

initialize_state() {
  local uid gid manual_repair
  uid="$(id --user)"
  gid="$(id --group)"
  manual_repair="give ${STATE_DIR} and ${AGENT_DIR} to UID ${uid} with mode 0700, and its auth.json and mcp-auth.json"
  manual_repair+=" mode 0600, then rerun ${SELF_PATH}"
  check_environment
  check_mount
  check_link
  if ! state_is_healthy "${uid}"; then
    if [[ "${uid}" == 0 ]]; then
      repair_state "${uid}" "${gid}"
    else
      command -v sudo >/dev/null || fail "state repair needs noninteractive sudo; ${manual_repair}"
      sudo --non-interactive "${SELF_PATH}" --repair "${uid}" "${gid}" \
        || fail "state repair failed; grant noninteractive sudo, or ${manual_repair}"
    fi
    state_is_healthy "${uid}" || fail "${STATE_DIR} is still not private to UID ${uid}; repair it manually"
  fi
  check_access
  create_link
  log "private project state is ready"
}

main() {
  if [[ "$#" == 3 && "$1" == --repair ]]; then
    repair_state "$2" "$3"
  elif [[ "$#" == 0 ]]; then
    initialize_state
  else
    fail "unexpected arguments; run ${SELF_PATH} without arguments"
  fi
}

main "$@"
