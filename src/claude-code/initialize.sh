#!/usr/bin/env bash
# Checks the project state mount once per container creation, as the remote user. A detected mismatch may invoke
# root repair through sudo; repairs stay inside /var/lib/claude-code without following external state symlinks.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/claude-code"
readonly SELF_PATH="/usr/local/share/claude-code-feature/initialize"

log() { printf 'claude-code: %s\n' "$*"; }
fail() { printf 'claude-code: error: %s\n' "$*" >&2; exit 1; }

# Root-only repair: $1 and $2 are the runtime user's numeric UID/GID, supplied through noninteractive sudo.
repair_state() {
  local uid="$1" gid="$2" owner
  [[ "$(id --user)" == 0 && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
    || fail "invalid repair identity; rerun initialization as the remote user"
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "state mount is unavailable; recreate the container with the feature's volume"
  fi
  owner="$(stat --format=%u "${STATE_DIR}")"
  if [[ "${owner}" != "${uid}" ]]; then
    log "repairing ownership inside ${STATE_DIR} for the remote user"
    find -P "${STATE_DIR}" -xdev -exec chown --no-dereference "${uid}:${gid}" -- {} +
    find -P "${STATE_DIR}" -xdev -type d -exec chmod 0700 -- {} +
    find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
  fi
  chmod 0700 "${STATE_DIR}"
  local file
  for file in .credentials.json .claude.json; do
    if [[ -f "${STATE_DIR}/${file}" && ! -L "${STATE_DIR}/${file}" ]]; then
      chown "${uid}:${gid}" "${STATE_DIR}/${file}"
      chmod 0600 "${STATE_DIR}/${file}"
    fi
  done
}

initialize_state() {
  local uid gid home_path needs_repair=false probe
  [[ "${CLAUDE_CONFIG_DIR+x}" != x ]] || fail "CLAUDE_CONFIG_DIR is configured; remove the override and rerun initialization"
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume"
  fi
  uid="$(id --user)"
  gid="$(id --group)"
  home_path="${HOME:-$(getent passwd "${uid}" | cut --delimiter=: --fields=6)}"
  [[ -d "${home_path}" && "${home_path}" == /* ]] || fail "remote-user home is unavailable; fix HOME and retry"
  [[ ! -e "${home_path}/.claude.json" && ! -L "${home_path}/.claude.json" ]] \
    || fail "existing .claude.json is outside the mapped home; preserve it and migrate it explicitly"
  if [[ -L "${home_path}/.claude" ]]; then
    [[ "$(readlink --canonicalize-existing "${home_path}/.claude")" == "${STATE_DIR}" ]] \
      || fail "existing .claude link conflicts; preserve it and resolve the mapping manually"
  elif [[ -e "${home_path}/.claude" ]]; then
    fail "existing .claude content conflicts; preserve it and migrate it explicitly"
  fi
  if [[ "$(stat --format=%u:%a "${STATE_DIR}")" != "${uid}:700" \
    || ! -r "${STATE_DIR}" || ! -w "${STATE_DIR}" || ! -x "${STATE_DIR}" ]]; then
    needs_repair=true
  fi
  if [[ "${needs_repair}" == false ]]; then
    for probe in .credentials.json .claude.json; do
      if [[ -e "${STATE_DIR}/${probe}" \
        && "$(stat --format=%u:%a "${STATE_DIR}/${probe}")" != "${uid}:600" ]]; then
        needs_repair=true
      fi
    done
  fi
  if [[ "${needs_repair}" == true ]]; then
    if [[ "${uid}" == 0 ]]; then
      repair_state "${uid}" "${gid}"
    else
      command -v sudo >/dev/null || fail "state repair needs noninteractive sudo; repair the volume owner manually"
      sudo --non-interactive "${SELF_PATH}" --repair "${uid}" "${gid}" \
        || fail "state repair failed; grant noninteractive sudo or repair the volume owner manually"
    fi
  fi
  for probe in .claude.json .credentials.json; do
    [[ ! -L "${STATE_DIR}/${probe}" ]] || fail "${probe} is a symlink; preserve it and resolve the state mapping"
  done
  [[ -r "${STATE_DIR}" && -w "${STATE_DIR}" && -x "${STATE_DIR}" ]] \
    || fail "state is inaccessible; repair the volume permissions and retry"
  probe="$(mktemp "${STATE_DIR}/.claude-feature-check.XXXXXX")" \
    || fail "state is not writable; repair the volume permissions and retry"
  rm -- "${probe}"
  if [[ ! -L "${home_path}/.claude" ]]; then
    log "linking the runtime home to ${STATE_DIR}"
    ln --symbolic "${STATE_DIR}" "${home_path}/.claude"
  fi
  [[ ! -e "${STATE_DIR}/.claude.json" ]] || chmod 0600 "${STATE_DIR}/.claude.json"
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
