#!/usr/bin/env bash
# Checks the OpenCode project state once per container creation, as the remote user: the /var/lib/opencode mount, the
# links from the effective XDG directories, ownership, private permissions, and access. A detected ownership or
# permission mismatch reruns this script as root through noninteractive sudo (--repair UID GID), which repairs only
# inside the mount and never follows symlinks out of it.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/opencode"
readonly SELF_PATH="/usr/local/share/opencode-feature/initialize"
readonly STATE_KINDS=(data config state cache)
readonly CREDENTIAL_FILES=(data/opencode.db data/opencode.db-wal data/opencode.db-shm)

log() {
  printf 'opencode: %s\n' "$*"
}

fail() {
  printf 'opencode: error: %s\n' "$*" >&2
  exit 1
}

# Fails unless the feature's volume is mounted at /var/lib/opencode.
check_mount() {
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume"
  fi
}

# Prints the effective XDG root for OpenCode's directory of kind $1, from XDG_*_HOME or its default under HOME.
effective_root() {
  local root
  case "$1" in
    data) root="${XDG_DATA_HOME:-${HOME}/.local/share}" ;;
    config) root="${XDG_CONFIG_HOME:-${HOME}/.config}" ;;
    state) root="${XDG_STATE_HOME:-${HOME}/.local/state}" ;;
    cache) root="${XDG_CACHE_HOME:-${HOME}/.cache}" ;;
  esac
  [[ "${root}" == /* ]] || fail "the XDG root for OpenCode ${1} is \"${root}\"; use an absolute path"
  printf '%s\n' "${root}"
}

# Root-only repair: $1 and $2 are the remote user's numeric UID and GID, passed through noninteractive sudo.
repair_state() {
  local uid="$1" gid="$2" kind file
  [[ "$(id --user)" == 0 && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
    || fail "invalid repair request; rerun ${SELF_PATH} without arguments as the remote user"
  check_mount
  if [[ "$(stat --format=%u "${STATE_DIR}")" != "${uid}" ]]; then
    log "repairing ownership inside ${STATE_DIR} for UID ${uid}"
    find -P "${STATE_DIR}" -xdev -exec chown --no-dereference "${uid}:${gid}" -- {} +
    find -P "${STATE_DIR}" -xdev -type d -exec chmod 0700 -- {} +
    find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
  fi
  chmod 0700 "${STATE_DIR}"
  for kind in "${STATE_KINDS[@]}"; do
    if [[ -L "${STATE_DIR}/${kind}" ]]; then fail "${STATE_DIR}/${kind} is a symlink; resolve it manually"; fi
    if [[ ! -e "${STATE_DIR}/${kind}" ]]; then
      install --directory --mode 0700 --owner "${uid}" --group "${gid}" "${STATE_DIR}/${kind}"
    fi
    chmod 0700 "${STATE_DIR}/${kind}"
  done
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -f "${STATE_DIR}/${file}" && ! -L "${STATE_DIR}/${file}" ]]; then
      chown "${uid}:${gid}" "${STATE_DIR}/${file}"
      chmod 0600 "${STATE_DIR}/${file}"
    fi
  done
}

# Fails on any OpenCode XDG path that is not missing and not a link to its volume directory; changes nothing.
check_links() {
  local kind root path
  for kind in "${STATE_KINDS[@]}"; do
    root="$(effective_root "${kind}")"
    path="${root}/opencode"
    if [[ -L "${path}" ]]; then
      [[ "$(readlink "${path}")" == "${STATE_DIR}/${kind}" ]] \
        || fail "${path} links elsewhere; preserve it and resolve the mapping manually"
    elif [[ -e "${path}" ]]; then
      fail "${path} already exists; back it up and migrate it explicitly before using this feature"
    elif [[ -e "${root}" && ! -d "${root}" ]]; then
      fail "${root} is not a directory; move it aside and rerun ${SELF_PATH}"
    fi
  done
}

# Succeeds when the state root, its directories, and the credential database have the remote user's private modes.
state_is_healthy() {
  local uid="$1" kind file
  [[ "$(stat --format=%u:%a "${STATE_DIR}")" == "${uid}:700" ]] || return 1
  for kind in "${STATE_KINDS[@]}"; do
    [[ -d "${STATE_DIR}/${kind}" && ! -L "${STATE_DIR}/${kind}" ]] || return 1
    [[ "$(stat --format=%u:%a "${STATE_DIR}/${kind}")" == "${uid}:700" ]] || return 1
  done
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -e "${STATE_DIR}/${file}" ]]; then
      [[ ! -L "${STATE_DIR}/${file}" && "$(stat --format=%u:%a "${STATE_DIR}/${file}")" == "${uid}:600" ]] || return 1
    fi
  done
}

# Proves that the remote user can create and remove a file in each state directory.
check_access() {
  local kind probe
  for kind in "${STATE_KINDS[@]}"; do
    probe="$(mktemp "${STATE_DIR}/${kind}/.opencode-feature-check.XXXXXX")" \
      || fail "${STATE_DIR}/${kind} is not writable; repair the volume permissions and rerun ${SELF_PATH}"
    rm -- "${probe}"
  done
}

create_links() {
  local kind root
  for kind in "${STATE_KINDS[@]}"; do
    root="$(effective_root "${kind}")"
    if [[ ! -L "${root}/opencode" ]]; then
      log "linking ${root}/opencode to ${STATE_DIR}/${kind}"
      # XDG roots are shared with other tools, so they keep the usual mode rather than the private umask.
      (umask 022 && mkdir --parents "${root}")
      ln --symbolic --no-target-directory "${STATE_DIR}/${kind}" "${root}/opencode"
    fi
  done
}

initialize_state() {
  local uid gid
  uid="$(id --user)"
  gid="$(id --group)"
  [[ "${HOME:-}" == /* && -d "${HOME}" ]] || fail "the remote user's HOME is unavailable; fix HOME and retry"
  check_mount
  check_links
  if ! state_is_healthy "${uid}"; then
    if [[ "${uid}" == 0 ]]; then
      repair_state "${uid}" "${gid}"
    else
      command -v sudo >/dev/null \
        || fail "state repair needs noninteractive sudo; restore ${STATE_DIR} ownership to UID ${uid} manually"
      sudo --non-interactive "${SELF_PATH}" --repair "${uid}" "${gid}" \
        || fail "state repair failed; grant noninteractive sudo or restore ${STATE_DIR} ownership to UID ${uid}"
    fi
    state_is_healthy "${uid}" || fail "${STATE_DIR} is still not private to UID ${uid}; repair it manually"
  fi
  check_access
  create_links
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
