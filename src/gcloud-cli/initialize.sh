#!/usr/bin/env bash
# Checks the gcloud-cli state mount once per container creation, as the remote user, and links ~/.config/gcloud into it.
# A detected ownership mismatch may invoke root repair through noninteractive sudo; repair stays inside
# /var/lib/gcloud-cli and never follows symlinks out of it.
set -euo pipefail
umask 077

readonly STATE_DIR="/var/lib/gcloud-cli"
readonly STATE_CONFIG_DIR="/var/lib/gcloud-cli/config"
readonly SELF_PATH="/usr/local/share/gcloud-cli-feature/initialize"
readonly STATE_DIRS=("config" "config/legacy_credentials")
readonly CREDENTIAL_FILES=(
  "config/credentials.db"
  "config/access_tokens.db"
  "config/application_default_credentials.json"
)

log() {
  printf 'gcloud-cli: %s\n' "$*"
}

fail() {
  printf 'gcloud-cli: error: %s\n' "$*" >&2
  exit 1
}

# Fails unless the state root is the mounted volume rather than ephemeral image storage.
require_mount() {
  if [[ -L "${STATE_DIR}" ]] || ! mountpoint --quiet "${STATE_DIR}"; then
    fail "${STATE_DIR} is not mounted; recreate the container with the feature's named volume"
  fi
}

# Rejects symlinks at known state subdirectories and credential paths before changing ownership or permissions.
check_state_links() {
  local name
  for name in "${STATE_DIRS[@]}" "${CREDENTIAL_FILES[@]}"; do
    [[ ! -L "${STATE_DIR}/${name}" ]] \
      || fail "${STATE_DIR}/${name} is a symlink; preserve it and resolve the mapping manually"
  done
}

# Restores private modes on the state root, its known subdirectories, and known credential files without recursion.
restore_modes() {
  local name file
  check_state_links
  chmod u=rwx,go=,ug-s,o-t "${STATE_DIR}"
  for name in "${STATE_DIRS[@]}"; do
    if [[ -d "${STATE_DIR}/${name}" && ! -L "${STATE_DIR}/${name}" ]]; then
      chmod u=rwx,go=,ug-s,o-t "${STATE_DIR}/${name}"
    fi
  done
  for file in "${CREDENTIAL_FILES[@]}"; do
    if [[ -f "${STATE_DIR}/${file}" && ! -L "${STATE_DIR}/${file}" ]]; then
      chmod 0600 "${STATE_DIR}/${file}"
    fi
  done
}

# Root-only repair: $1 and $2 are the runtime user's numeric UID and GID, supplied through noninteractive sudo.
repair_state() {
  local uid="$1"
  local gid="$2"
  [[ "$(id --user)" == 0 && "${uid}" =~ ^[0-9]+$ && "${gid}" =~ ^[0-9]+$ ]] \
    || fail "invalid repair identity; rerun initialization as the remote user"
  require_mount
  check_state_links
  log "repairing ownership inside ${STATE_DIR} for UID ${uid}"
  find -P "${STATE_DIR}" -xdev -exec chown --no-dereference "${uid}:${gid}" -- {} +
  find -P "${STATE_DIR}" -xdev -type d -exec chmod u=rwx,go=,ug-s,o-t -- {} +
  find -P "${STATE_DIR}" -xdev -type f -exec chmod go-rwx -- {} +
  restore_modes
}

# Fails when CLOUDSDK_CONFIG is explicitly set to a path outside $1 (~/.config/gcloud) and STATE_CONFIG_DIR.
check_cloudsdk_config_override() {
  local link_path="$1"
  local resolved_override resolved_link
  if [[ -z "${CLOUDSDK_CONFIG:-}" ]]; then return; fi
  [[ "${CLOUDSDK_CONFIG}" == /* ]] \
    || fail "CLOUDSDK_CONFIG is \"${CLOUDSDK_CONFIG}\", outside ${link_path}; unset it or point it at ${link_path}"
  resolved_override="$(readlink --canonicalize-missing "${CLOUDSDK_CONFIG}")"
  resolved_link="$(readlink --canonicalize-missing "${link_path}")"
  if [[ "${resolved_override}" != "${STATE_CONFIG_DIR}" && "${resolved_override}" != "${resolved_link}" ]]; then
    fail "CLOUDSDK_CONFIG points to \"${CLOUDSDK_CONFIG}\" outside the mapped volume; unset it or preserve" \
      "external state manually"
  fi
}

initialize_state() {
  local uid gid home_path config_dir link_path name file probe
  local repair="none"
  require_mount
  check_state_links
  uid="$(id --user)"
  gid="$(id --group)"
  home_path="${HOME:-$(getent passwd "${uid}" | cut --delimiter=: --fields=6 || true)}"
  [[ "${home_path}" == /* && -d "${home_path}" ]] || fail "remote-user home is unavailable; fix HOME and retry"
  config_dir="${home_path}/.config"
  link_path="${config_dir}/gcloud"
  check_cloudsdk_config_override "${link_path}"

  if [[ -e "${config_dir}" && ! -d "${config_dir}" ]]; then
    fail "existing ${config_dir} is not a directory; preserve it and resolve the mapping manually"
  fi
  if [[ -L "${link_path}" ]]; then
    [[ "$(readlink --canonicalize-missing "${link_path}")" == "${STATE_CONFIG_DIR}" ]] \
      || fail "existing ${link_path} link points elsewhere; preserve it and resolve the mapping manually"
  elif [[ -e "${link_path}" ]]; then
    fail "existing ${link_path} conflicts; preserve it and migrate it explicitly"
  fi

  if [[ "$(stat --format=%u "${STATE_DIR}")" != "${uid}" ]]; then repair="ownership"; fi
  for name in "${STATE_DIRS[@]}" "${CREDENTIAL_FILES[@]}"; do
    if [[ -e "${STATE_DIR}/${name}" && "$(stat --format=%u "${STATE_DIR}/${name}")" != "${uid}" ]]; then
      repair="ownership"
    fi
  done
  if [[ "${repair}" == none ]]; then
    if [[ "$(stat --format=%a "${STATE_DIR}")" != 700 ]]; then repair="modes"; fi
    for name in "${STATE_DIRS[@]}"; do
      if [[ -d "${STATE_DIR}/${name}" && "$(stat --format=%a "${STATE_DIR}/${name}")" != 700 ]]; then
        repair="modes"
      fi
    done
    for file in "${CREDENTIAL_FILES[@]}"; do
      if [[ -f "${STATE_DIR}/${file}" && "$(stat --format=%a "${STATE_DIR}/${file}")" != 600 ]]; then
        repair="modes"
      fi
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

  check_state_links
  if [[ ! -e "${STATE_CONFIG_DIR}" ]]; then mkdir --mode 0700 "${STATE_CONFIG_DIR}"; fi
  [[ -d "${STATE_CONFIG_DIR}" && -r "${STATE_CONFIG_DIR}" && -w "${STATE_CONFIG_DIR}" && -x "${STATE_CONFIG_DIR}" ]] \
    || fail "${STATE_CONFIG_DIR} is inaccessible; repair the volume and retry"
  probe="$(mktemp "${STATE_CONFIG_DIR}/.gcloud-cli-feature-check.XXXXXX")" \
    || fail "${STATE_CONFIG_DIR} is not writable; repair the volume permissions and retry"
  rm -- "${probe}"

  if [[ ! -L "${link_path}" ]]; then
    log "linking ${link_path} to ${STATE_CONFIG_DIR}"
    mkdir --parents "${config_dir}"
    ln --symbolic --no-target-directory "${STATE_CONFIG_DIR}" "${link_path}"
  fi
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
