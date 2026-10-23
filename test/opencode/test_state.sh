#!/usr/bin/env bash
# Exercises the initializer and the real CLI on the mounted project state with synthetic fixtures only: no login, no
# real key, and no model request.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/opencode-feature/initialize"
readonly STATE_DIR="/var/lib/opencode"
readonly PROJECT="/tmp/opencode-session-fixture"
FIXTURES="$(cd "$(dirname "$0")" && pwd)"
readonly FIXTURES
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${PROJECT}"

"${INITIALIZE}"

# find and sudo both fail here, so a scan or a repair, which runs through sudo with its own PATH, fails the check.
healthy_without_scan() {
  local output
  mkdir "${work}/no-scan"
  printf '#!/bin/sh\nexit 91\n' >"${work}/no-scan/find"
  cp "${work}/no-scan/find" "${work}/no-scan/sudo"
  chmod +x "${work}/no-scan/find" "${work}/no-scan/sudo"
  output="$(PATH="${work}/no-scan:${PATH}" "${INITIALIZE}")" || return 1
  [[ "${output}" != *repairing* ]]
}
check "a healthy volume initializes without a full-tree scan or repair" healthy_without_scan

rejects_initialization() {
  local output
  if output="$("${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"opencode: error:"* ]]
}
missing_mount() {
  mkdir "${work}/no-mount"
  printf '#!/bin/sh\nexit 1\n' >"${work}/no-mount/mountpoint"
  chmod +x "${work}/no-mount/mountpoint"
  PATH="${work}/no-mount:${PATH}" rejects_initialization
}
check "a missing mount is rejected instead of treated as persistent state" missing_mount
check "start and attach hooks run no state check" \
  jq -e 'has("postStartCommand") or has("postAttachCommand") | not' "${FIXTURES}/_feature/devcontainer-feature.json"

imports_credential() {
  (cd "${PROJECT}" && opencode auth import --standalone "${FIXTURES}/credential_fixture.json" >/dev/null) || return 1
  [[ "$(stat -c %a "${STATE_DIR}/data/opencode.db")" == 600 ]]
}
check "a synthetic credential is stored privately in the volume" imports_credential
lists_credential() {
  local output
  output="$(cd "${PROJECT}" && opencode auth list --standalone)"
  [[ "${output}" == *"Synthetic fixture"* ]]
}
check "a fresh CLI process reads the stored credential" lists_credential

imports_session() {
  (cd "${PROJECT}" && opencode session import --standalone "${FIXTURES}/session_fixture.json" >/dev/null)
}
check "the CLI saves an imported synthetic session" imports_session
lists_session() {
  local output
  output="$(cd "${PROJECT}" && opencode session list --standalone --format json)"
  [[ "${output}" == *ses_fixture0000000000000000001* ]]
}
check "a fresh CLI process reopens the saved session" lists_session

replaces_configuration() {
  printf '{"autoupdate":false}\n' >"${work}/opencode.json"
  cp "${work}/opencode.json" "${HOME}/.config/opencode/.opencode.json.next"
  mv "${HOME}/.config/opencode/.opencode.json.next" "${HOME}/.config/opencode/opencode.json"
  [[ -L "${HOME}/.config/opencode" && -f "${STATE_DIR}/config/opencode.json" ]] || return 1
  "${INITIALIZE}" || return 1
  cmp "${work}/opencode.json" "${STATE_DIR}/config/opencode.json"
}
check "an atomically replaced configuration stays in the volume and initialization keeps it" replaces_configuration

# Runs the initializer with a conflicting entry at the configuration path and restores the real link afterwards.
conflict_preserved() {
  local kind="$1" path="${HOME}/.config/opencode" result=0
  mv "${path}" "${work}/config-link"
  case "${kind}" in
    file) printf 'keep\n' >"${path}" ;;
    directory) mkdir "${path}" && printf 'keep\n' >"${path}/marker" ;;
    dangling) ln -s /tmp/opencode-missing-target "${path}" ;;
    foreign) mkdir "${work}/foreign" && ln -s "${work}/foreign" "${path}" ;;
  esac
  rejects_initialization || result=1
  case "${kind}" in
    file) [[ "$(cat "${path}")" == keep ]] || result=1 ;;
    directory) [[ "$(cat "${path}/marker")" == keep ]] || result=1 ;;
    dangling) [[ "$(readlink "${path}")" == /tmp/opencode-missing-target ]] || result=1 ;;
    foreign) [[ "$(readlink "${path}")" == "${work}/foreign" ]] || result=1 ;;
  esac
  rm -r "${path}"
  mv "${work}/config-link" "${path}"
  cmp "${work}/opencode.json" "${STATE_DIR}/config/opencode.json" || result=1
  return "${result}"
}
for kind in file directory dangling foreign; do
  check "an existing ${kind} at the configuration path is reported and preserved" conflict_preserved "${kind}"
done

# Prints the default XDG root, relative to the home directory, of OpenCode's directory of kind $1.
default_root() {
  case "$1" in
    data) printf '.local/share\n' ;;
    config) printf '.config\n' ;;
    state) printf '.local/state\n' ;;
    cache) printf '.cache\n' ;;
  esac
}
new_home() {
  local kind
  mkdir -p "${work}/home/.config/other-tool"
  printf 'other\n' >"${work}/home/.config/other-tool/marker"
  HOME="${work}/home" "${INITIALIZE}" || return 1
  for kind in data config state cache; do
    [[ -d "${work}/home/$(default_root "${kind}")/opencode/" ]] || return 1
  done
  [[ "$(readlink "${work}/home/.config/opencode")" == "${STATE_DIR}/config" ]] || return 1
  [[ "$(cat "${work}/home/.config/other-tool/marker")" == other ]]
}
check "a different runtime home gets its links and keeps other tools' data" new_home

custom_roots() {
  local kind output
  mkdir -p "${work}/xdg/config/other-tool"
  printf 'other\n' >"${work}/xdg/config/other-tool/marker"
  XDG_DATA_HOME="${work}/xdg/data" XDG_CONFIG_HOME="${work}/xdg/config" XDG_STATE_HOME="${work}/xdg/state" \
    XDG_CACHE_HOME="${work}/xdg/cache" "${INITIALIZE}" || return 1
  for kind in data config state cache; do
    [[ "$(readlink "${work}/xdg/${kind}/opencode")" == "${STATE_DIR}/${kind}" ]] || return 1
  done
  [[ "$(cat "${work}/xdg/config/other-tool/marker")" == other ]] || return 1
  output="$(cd "${PROJECT}" && XDG_DATA_HOME="${work}/xdg/data" XDG_CONFIG_HOME="${work}/xdg/config" \
    XDG_STATE_HOME="${work}/xdg/state" XDG_CACHE_HOME="${work}/xdg/cache" opencode session list --standalone)"
  [[ "${output}" == *ses_fixture0000000000000000001* ]]
}
check "custom XDG roots map only the OpenCode directories and reach the same state" custom_roots
check "a relative XDG root is rejected" env XDG_CONFIG_HOME=relative bash -c "! '${INITIALIZE}'"

private_database_repaired() {
  chmod 0644 "${STATE_DIR}/data/opencode.db"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %a "${STATE_DIR}/data/opencode.db")" == 600 ]]
}
check "a readable credential database is made private again" private_database_repaired

changed_uid() {
  local before
  printf 'outside\n' >"${work}/external"
  chmod 0644 "${work}/external"
  # Owned by neither the remote user nor the fake UID, so a repair that follows the link changes it visibly.
  sudo chown root:root "${work}/external"
  before="$(stat -c %u:%g:%a "${work}/external")"
  ln -s "${work}/external" "${STATE_DIR}/state/external-link"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == "$(id -u):700" \
    && "$(stat -c %u:%a "${STATE_DIR}/data/opencode.db")" == "$(id -u):600" \
    && "$(stat -c %u:%g:%a "${work}/external")" == "${before}" ]]
}
check "a changed UID is repaired without changing external link targets" changed_uid

unavailable_repair() {
  local result=0
  mkdir "${work}/no-sudo"
  printf '#!/bin/sh\nexit 1\n' >"${work}/no-sudo/sudo"
  chmod +x "${work}/no-sudo/sudo"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  PATH="${work}/no-sudo:${PATH}" rejects_initialization || result=1
  # The remote user cannot enter the foreign-owned root, so root inspects what is left.
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == 23456:700 ]] || result=1
  sudo test -f "${STATE_DIR}/data/opencode.db" || result=1
  "${INITIALIZE}" || return 1
  return "${result}"
}
check "unavailable repair fails without broadening access or deleting state" unavailable_repair

replacement_keeps_state() {
  local current
  current="$(opencode --version)"
  current="${current#opencode v}"
  sudo env PATH="${PATH}" VERSION=2.1.2 _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${FIXTURES}/_feature/install.sh" || return 1
  [[ "$(opencode --version)" == "opencode v2.1.2" ]] || return 1
  sudo env PATH="${PATH}" VERSION="${current}" _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${FIXTURES}/_feature/install.sh" || return 1
  [[ "$(opencode --version)" == "opencode v${current}" ]] || return 1
  lists_credential && lists_session && cmp "${work}/opencode.json" "${STATE_DIR}/config/opencode.json"
}
same_release_skipped() {
  local current before output
  current="$(opencode --version)"
  before="$(stat -c %i:%Y /usr/local/bin/opencode)"
  output="$(sudo env PATH="${PATH}" VERSION="${current#opencode v}" _REMOTE_USER="$(id -un)" \
    _REMOTE_USER_HOME="${HOME}" bash "${FIXTURES}/_feature/install.sh")" || return 1
  [[ "${output}" == *"is already installed at /usr/local/bin/opencode"* \
    && "$(stat -c %i:%Y /usr/local/bin/opencode)" == "${before}" ]] || return 1
  lists_credential && lists_session
}
check "installing the same release again skips the replacement and keeps state" same_release_skipped
check "another release replaces the CLI and keeps credentials, sessions, and configuration" replacement_keeps_state
reportResults
