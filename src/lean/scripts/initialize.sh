#!/usr/bin/env bash
# Prepares the per-dev-container volume at /var/lib/lean for the remote user each time a dev container is created:
# makes the remote user its owner, through passwordless sudo, when another UID wrote it; creates elan's home and the
# Lake and Mathlib cache directories in it; links the build-time toolchains of /usr/local/share/lean/toolchains into
# elan's home; and sets elan's default toolchain from /usr/local/share/lean-feature/default-toolchain. install.sh
# installs it as /usr/local/share/lean-feature/initialize, and onCreateCommand runs it as the remote user, before the
# user's creation commands. It takes no options.
#
# A failed step must not stop the creation of the dev container (openspec/specs/lean/spec.md, "Continue when the volume
# cannot be prepared"). So, unlike the shell style guide's skeleton, this script enables neither set -e nor set -u,
# every path through main returns 0, and it defines warn instead of an exiting fail.

readonly VOLUME_DIR="/var/lib/lean"
readonly ELAN_HOME_DIR="${VOLUME_DIR}/elan"
readonly VOLUME_TOOLCHAINS_DIR="${ELAN_HOME_DIR}/toolchains"
readonly CACHE_DIRS=("${VOLUME_DIR}/cache/lake" "${VOLUME_DIR}/cache/mathlib")
readonly IMAGE_TOOLCHAINS_DIR="/usr/local/share/lean/toolchains"
readonly DEFAULT_TOOLCHAIN_PATH="/usr/local/share/lean-feature/default-toolchain"
readonly ELAN_PATH="/usr/local/bin/elan"
readonly GROUP="lean"

log() {
  printf 'lean: %s\n' "$*"
}

# Prints a warning about the volume to standard error; $1 is the reason.
warn() {
  printf '%s\n' "lean: warning: ${VOLUME_DIR}: $1; see the lean feature's NOTES.md" >&2
}

# Whether the volume fits the user with the UID $1: that user can create files in it and owns everything below it.
# find -P follows no symbolic link.
volume_fits() {
  local foreign
  if [[ ! -w "${VOLUME_DIR}" || ! -x "${VOLUME_DIR}" ]]; then return 1; fi
  if ! foreign="$(find -P "${VOLUME_DIR}" -mindepth 1 ! -user "$1" -print -quit 2>&1)"; then return 1; fi
  [[ -z "${foreign}" ]]
}

# Makes the remote user, with the UID $1, the owner of a volume that does not fit, through passwordless sudo.
repair_volume() {
  local reason group owner
  if [[ "$1" == "0" ]] || volume_fits "$1"; then return 0; fi
  if ! command -v sudo >/dev/null 2>&1; then
    warn "the volume does not fit this user and sudo is unavailable"
    return 0
  fi
  # sudo keeps its short option -n: it is the sudo of the user's image, whose long options are not checked here.
  if ! reason="$(sudo -n true 2>&1)"; then
    warn "the volume does not fit this user and passwordless sudo is unavailable: ${reason}"
    return 0
  fi
  group="$(awk -F: -v group="${GROUP}" '$1 == group {print $3}' /etc/group)"
  owner="$1"
  if [[ -n "${group}" ]]; then owner="$1:${group}"; fi
  log "making ${owner} the owner of ${VOLUME_DIR} and everything in it"
  # --no-dereference keeps a symbolic link from changing its target, and -P keeps the recursion from following links
  # into the image's toolchains or anywhere else. It may clear setuid and setgid on executable files; it runs no chmod.
  if ! reason="$(sudo -n chown --no-dereference --recursive -P "${owner}" "${VOLUME_DIR}" 2>&1)"; then
    warn "cannot change the volume's owner: ${reason}"
  fi
}

prepare_directories() {
  local directory reason
  for directory in "${VOLUME_TOOLCHAINS_DIR}" "${CACHE_DIRS[@]}"; do
    if [[ -d "${directory}" ]]; then continue; fi
    if ! reason="$(mkdir --parents "${directory}" 2>&1)"; then
      warn "cannot create ${directory}: ${reason}"
    fi
  done
}

# Removes links in elan's toolchains directory that point into the image's toolchains and no longer resolve, then links
# each image toolchain that has no entry of its name there yet.
link_toolchains() {
  local entry target name reason
  if [[ ! -d "${VOLUME_TOOLCHAINS_DIR}" ]]; then return 0; fi
  shopt -s nullglob
  for entry in "${VOLUME_TOOLCHAINS_DIR}"/*; do
    if [[ ! -L "${entry}" || -e "${entry}" ]]; then continue; fi
    target="$(readlink -- "${entry}")"
    if [[ "${target}" != "${IMAGE_TOOLCHAINS_DIR}/"* ]]; then continue; fi
    log "removing ${entry}, whose toolchain the image no longer holds"
    if ! reason="$(rm --force -- "${entry}" 2>&1)"; then
      warn "cannot remove ${entry}: ${reason}"
    fi
  done
  for entry in "${IMAGE_TOOLCHAINS_DIR}"/*; do
    name="${entry##*/}"
    if [[ ! -d "${entry}" || -e "${VOLUME_TOOLCHAINS_DIR}/${name}" || -L "${VOLUME_TOOLCHAINS_DIR}/${name}" ]]; then
      continue
    fi
    log "linking the build-time toolchain ${name} into ${VOLUME_TOOLCHAINS_DIR}"
    if ! reason="$(ln --symbolic -- "${entry}" "${VOLUME_TOOLCHAINS_DIR}/${name}" 2>&1)"; then
      warn "cannot link ${entry}: ${reason}"
    fi
  done
  shopt -u nullglob
}

# Sets elan's default toolchain to the one install.sh recorded, unless that is empty; elan stores the name unresolved
# and downloads nothing.
set_default_toolchain() {
  local toolchain reason
  if [[ ! -r "${DEFAULT_TOOLCHAIN_PATH}" ]]; then
    warn "cannot read ${DEFAULT_TOOLCHAIN_PATH}, so elan's default toolchain is unchanged"
    return 0
  fi
  toolchain="$(<"${DEFAULT_TOOLCHAIN_PATH}")"
  if [[ -z "${toolchain}" ]]; then return 0; fi
  if ! reason="$(ELAN_HOME="${ELAN_HOME_DIR}" "${ELAN_PATH}" default "${toolchain}" 2>&1)"; then
    warn "cannot set elan's default toolchain to ${toolchain}: ${reason}"
  fi
}

main() {
  local uid
  if ! uid="$(id -u)"; then
    warn "cannot determine the remote user's UID"
    return 0
  fi
  repair_volume "${uid}"
  prepare_directories
  link_toolchains
  set_default_toolchain
  return 0
}

main "$@"
