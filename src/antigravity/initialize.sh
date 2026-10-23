#!/usr/bin/env bash
# Checks the Antigravity state mount once per container creation, as the remote user, and links the user's effective
# Antigravity state directories into it. A detected ownership mismatch may invoke root repair through noninteractive
# sudo; repair stays inside /var/lib/antigravity and never follows symlinks out of it.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/antigravity"
readonly SELF_PATH="/usr/local/share/antigravity-feature/initialize"
readonly STATE_NAMES=("cli" "gemini-config" "plugin-secrets")
# Credential files kept at 0600, relative to the state root.
readonly CREDENTIAL_FILES=("cli/antigravity-oauth-token" "plugin-secrets/plugin-secrets.json")

log() {
  printf 'antigravity: %s\n' "$*"
}

fail() {
  printf 'antigravity: error: %s\n' "$*" >&2
  exit 1
}

# Fails unless the state root is the mounted volume rather than image storage.
require_mount() {
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume"
  fi
}

# Restores private modes on the state root, its subdirectories, and the known credential files, without recursion.
restore_modes() {
  local name file
  chmod 0700 "${STATE_DIR}"
  for name in "${STATE_NAMES[@]}"; do
    if [[ -d "${STATE_DIR}/${name}" && ! -L "${STATE_DIR}/${name}" ]]; then chmod 0700 "${STATE_DIR}/${name}"; fi
  done
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -f "${STATE_DIR}/${file}" && ! -L "${STATE_DIR}/${file}" ]]; then chmod 0600 "${STATE_DIR}/${file}"; fi
  done
}

# Root-only repair: $1 and $2 are the runtime user's numeric UID and GID, supplied through noninteractive sudo.
repair_state() {
  local uid="$1"
  local gid="$2"
  [[ "$(id --user)" == 0 && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
    || fail "invalid repair identity; rerun initialization as the remote user"
  require_mount
  log "repairing ownership inside ${STATE_DIR} for UID ${uid}"
  find -P "${STATE_DIR}" -xdev -exec chown --no-dereference "${uid}:${gid}" -- {} +
  find -P "${STATE_DIR}" -xdev -type d -exec chmod 0700 -- {} +
  find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
  restore_modes
}

initialize_state() {
  local uid gid home_path config_home mapping link_path target name file probe
  local mappings=()
  local repair=none
  require_mount
  uid="$(id --user)"
  gid="$(id --group)"
  home_path="${HOME:-$(getent passwd "${uid}" | cut --delimiter=: --fields=6)}"
  [[ "${home_path}" == /* && -d "${home_path}" ]] || fail "remote-user home is unavailable; fix HOME and retry"
  config_home="${XDG_CONFIG_HOME:-${home_path}/.config}"
  [[ "${config_home}" == /* ]] || fail "XDG_CONFIG_HOME is not an absolute path; fix it and rerun initialization"
  # Each mapping is <effective link path>:<state subdirectory>, in the order of STATE_NAMES.
  mappings=("${home_path}/.gemini/antigravity-cli:cli" "${home_path}/.gemini/config:gemini-config"
    "${config_home}/antigravity:plugin-secrets")
  for mapping in "${mappings[@]}"; do
    link_path="${mapping%:*}"
    target="${STATE_DIR}/${mapping##*:}"
    if [[ -L "${link_path}" ]]; then
      [[ "$(readlink --canonicalize-missing "${link_path}")" == "${target}" ]] \
        || fail "existing ${link_path} link points elsewhere; preserve it and resolve the mapping manually"
    elif [[ -e "${link_path}" ]]; then
      fail "existing ${link_path} conflicts; preserve it and migrate it explicitly"
    fi
  done
  # The root is checked by its own path: when it is inaccessible, nothing inside it can be inspected.
  if [[ "$(stat --format=%u "${STATE_DIR}")" != "${uid}" ]]; then repair=ownership; fi
  for name in "${STATE_NAMES[@]}" "${CREDENTIAL_FILES[@]}"; do
    if [[ -e "${STATE_DIR}/${name}" && "$(stat --format=%u "${STATE_DIR}/${name}")" != "${uid}" ]]; then
      repair=ownership
    fi
  done
  if [[ "${repair}" == none ]]; then
    if [[ "$(stat --format=%a "${STATE_DIR}")" != 700 ]]; then repair=modes; fi
    for name in "${STATE_NAMES[@]}"; do
      if [[ -d "${STATE_DIR}/${name}" && "$(stat --format=%a "${STATE_DIR}/${name}")" != 700 ]]; then repair=modes; fi
    done
    for file in "${CREDENTIAL_FILES[@]}"; do
      if [[ -f "${STATE_DIR}/${file}" && "$(stat --format=%a "${STATE_DIR}/${file}")" != 600 ]]; then repair=modes; fi
    done
  fi
  if [[ "${repair}" == ownership && "${uid}" == 0 ]]; then
    repair_state "${uid}" "${gid}"
  elif [[ "${repair}" == ownership ]]; then
    command -v sudo >/dev/null || fail "state repair needs noninteractive sudo; restore the volume owner manually"
    sudo --non-interactive "${SELF_PATH}" --repair "${uid}" "${gid}" \
      || fail "state repair failed; grant noninteractive sudo or restore the volume owner manually"
  elif [[ "${repair}" == modes ]]; then
    log "restoring private permissions inside ${STATE_DIR}"
    restore_modes
  fi
  for name in "${STATE_NAMES[@]}" "${CREDENTIAL_FILES[@]}"; do
    [[ ! -L "${STATE_DIR}/${name}" ]] || fail "${STATE_DIR}/${name} is a symlink; preserve it and resolve the mapping"
  done
  for name in "${STATE_NAMES[@]}"; do
    if [[ ! -e "${STATE_DIR}/${name}" ]]; then mkdir --mode 0700 "${STATE_DIR}/${name}"; fi
    [[ -d "${STATE_DIR}/${name}" && -r "${STATE_DIR}/${name}" && -w "${STATE_DIR}/${name}" \
      && -x "${STATE_DIR}/${name}" ]] || fail "${STATE_DIR}/${name} is inaccessible; repair the volume and retry"
    probe="$(mktemp "${STATE_DIR}/${name}/.antigravity-feature-check.XXXXXX")" \
      || fail "${STATE_DIR}/${name} is not writable; repair the volume permissions and retry"
    rm -- "${probe}"
  done
  for mapping in "${mappings[@]}"; do
    link_path="${mapping%:*}"
    target="${STATE_DIR}/${mapping##*:}"
    if [[ ! -L "${link_path}" ]]; then
      log "linking ${link_path} to ${target}"
      mkdir --parents "$(dirname "${link_path}")"
      ln --symbolic --no-target-directory "${target}" "${link_path}"
    fi
  done
  log "private project state is ready"
}

main() {
  if [[ "$#" == 3 && "$1" == --repair ]]; then
    repair_state "$2" "$3"
  else
    [[ "$#" == 0 ]] || fail "unexpected arguments; run initialize without arguments"
    initialize_state
  fi
}

main "$@"
