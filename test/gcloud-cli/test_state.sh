#!/usr/bin/env bash
# Scenario test_state: ubuntu24.04 (remoteUser vscode, --network=none). Exercises creation initialization,
# healthy-volume no-scan/no-sudo checks, real gcloud config writes, atomic synthetic credential persistence, conflict
# handling, CLOUDSDK_CONFIG rejection, bounded mode/ownership repair, and state symlink protection.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/gcloud-cli-feature/initialize"
readonly STATE_DIR="/var/lib/gcloud-cli"
readonly STATE_CONFIG="${STATE_DIR}/config"
readonly GCLOUD_HOME="${HOME}/.config/gcloud"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

"${INITIALIZE}"

healthy_without_scan() {
  local output
  mkdir -p "${work}/no-scan"
  printf '#!/bin/sh\nexit 91\n' >"${work}/no-scan/find"
  cp "${work}/no-scan/find" "${work}/no-scan/sudo"
  chmod +x "${work}/no-scan/find" "${work}/no-scan/sudo"
  output="$(PATH="${work}/no-scan:${PATH}" "${INITIALIZE}")" || return 1
  [[ "${output}" != *repairing* && "${output}" != *restoring* ]]
}
check "a healthy volume initializes without full-tree scans or sudo" healthy_without_scan
check "no postStartCommand or postAttachCommand is declared" jq -e \
  '(has("postStartCommand") or has("postAttachCommand")) | not' \
  "$(dirname "$0")/_feature/devcontainer-feature.json"

missing_mount() {
  mkdir -p "${work}/missing-mount"
  printf '#!/bin/sh\nexit 1\n' >"${work}/missing-mount/mountpoint"
  chmod +x "${work}/missing-mount/mountpoint"
  if PATH="${work}/missing-mount:${PATH}" "${INITIALIZE}"; then return 1; fi
}
check "a missing state mount fails instead of using ephemeral storage" missing_mount

check "CLOUDSDK_CONFIG is unset by default" test -z "${CLOUDSDK_CONFIG:-}"
resolves_to_volume() {
  local dir
  dir="$(gcloud info --format='value(config.paths.global_config_dir)')"
  [[ "$(readlink -f "${dir}")" == "${STATE_CONFIG}" ]]
}
check "gcloud global config resolves through .config/gcloud to the volume" resolves_to_volume

cli_writes_config() {
  gcloud config set core/project recreation-fixture-proj >/dev/null || return 1
  [[ -L "${GCLOUD_HOME}" && "$(readlink -f "${GCLOUD_HOME}")" == "${STATE_CONFIG}" ]] \
    && [[ -f "${STATE_CONFIG}/configurations/config_default" ]] \
    && [[ "$(gcloud config get-value core/project 2>/dev/null)" == "recreation-fixture-proj" ]]
}
check "real gcloud config writes stay volume-backed and readable" cli_writes_config

atomic_write() {
  printf 'synthetic %s fixture\n' "$2" >"$1.tmp"
  mv -f "$1.tmp" "$1"
}
atomic_credentials() {
  atomic_write "${GCLOUD_HOME}/credentials.db" cred-one
  atomic_write "${GCLOUD_HOME}/credentials.db" cred-two
  atomic_write "${GCLOUD_HOME}/access_tokens.db" token-one
  atomic_write "${GCLOUD_HOME}/application_default_credentials.json" adc-one
  [[ "$(cat "${STATE_CONFIG}/credentials.db")" == 'synthetic cred-two fixture' ]] \
    && [[ "$(cat "${STATE_CONFIG}/access_tokens.db")" == 'synthetic token-one fixture' ]] \
    && [[ "$(cat "${STATE_CONFIG}/application_default_credentials.json")" == 'synthetic adc-one fixture' ]] \
    && [[ -L "${GCLOUD_HOME}" ]]
}
check "atomically replaced synthetic credential fixtures stay volume-backed" atomic_credentials

private_without_printing() {
  local output
  output="$("${INITIALIZE}" 2>&1)" || return 1
  [[ "${output}" != *synthetic* ]] \
    && [[ "$(stat -c %a "${STATE_CONFIG}/credentials.db")" == 600 ]] \
    && [[ "$(stat -c %a "${STATE_CONFIG}/access_tokens.db")" == 600 ]] \
    && [[ "$(stat -c %a "${STATE_CONFIG}/application_default_credentials.json")" == 600 ]]
}
check "initialization enforces 0600 modes on credential files without printing contents" private_without_printing

unrelated_config_coexistence() {
  mkdir -p "${HOME}/.config/other-tool"
  printf 'other-tool-fixture\n' >"${HOME}/.config/other-tool/settings.json"
  "${INITIALIZE}" || return 1
  [[ "$(cat "${HOME}/.config/other-tool/settings.json")" == 'other-tool-fixture' ]] \
    && [[ ! -L "${HOME}/.config" && ! -e "${STATE_DIR}/other-tool" && ! -e "${STATE_CONFIG}/other-tool" ]]
}
check "unrelated .config directories stay outside the state volume" unrelated_config_coexistence

rejects_init() {
  local output
  if output="$("${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"gcloud-cli: error:"* ]]
}

link_conflicts() {
  local result=0
  mv "${GCLOUD_HOME}" "${work}/saved-link"

  mkdir "${GCLOUD_HOME}"
  printf 'keep\n' >"${GCLOUD_HOME}/marker"
  rejects_init || result=1
  [[ "$(cat "${GCLOUD_HOME}/marker")" == keep ]] || result=1
  rm -r "${GCLOUD_HOME}"

  printf 'keep\n' >"${GCLOUD_HOME}"
  rejects_init || result=1
  rm "${GCLOUD_HOME}"

  ln -s "${work}/nonexistent" "${GCLOUD_HOME}"
  rejects_init || result=1
  rm "${GCLOUD_HOME}"

  ln -s "${work}" "${GCLOUD_HOME}"
  rejects_init || result=1
  rm "${GCLOUD_HOME}"

  mv "${work}/saved-link" "${GCLOUD_HOME}"
  [[ "$(cat "${STATE_CONFIG}/credentials.db")" == 'synthetic cred-two fixture' ]] || result=1
  return "${result}"
}
check "conflicting existing directories, files, dangling links, and foreign links fail and preserve data" \
  link_conflicts

new_home() {
  mkdir -p "${work}/home"
  HOME="${work}/home" "${INITIALIZE}" || return 1
  [[ "$(readlink -f "${work}/home/.config/gcloud")" == "${STATE_CONFIG}" ]] \
    && [[ "$(cat "${work}/home/.config/gcloud/credentials.db")" == 'synthetic cred-two fixture' ]]
}
check "a different runtime HOME receives the missing symlink and reads saved state" new_home

cloudsdk_override() {
  local output
  if output="$(CLOUDSDK_CONFIG="${work}/outside-gcloud" "${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"CLOUDSDK_CONFIG"* && ! -e "${work}/outside-gcloud" ]] || return 1
  if output="$(CLOUDSDK_CONFIG="relative/gcloud" "${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"CLOUDSDK_CONFIG"* ]] || return 1
  CLOUDSDK_CONFIG="${GCLOUD_HOME}" "${INITIALIZE}" >/dev/null || return 1
  CLOUDSDK_CONFIG="${STATE_CONFIG}" "${INITIALIZE}" >/dev/null
}
check "CLOUDSDK_CONFIG outside mapped directory fails cleanly while mapped path succeeds" cloudsdk_override

mode_repair_without_sudo() {
  mkdir -p "${work}/no-sudo-modes"
  printf '#!/bin/sh\nexit 1\n' >"${work}/no-sudo-modes/sudo"
  chmod +x "${work}/no-sudo-modes/sudo"
  chmod 0755 "${STATE_CONFIG}"
  chmod 0644 "${STATE_CONFIG}/credentials.db"
  PATH="${work}/no-sudo-modes:${PATH}" "${INITIALIZE}" || return 1
  [[ "$(stat -c %a "${STATE_CONFIG}")" == 700 && "$(stat -c %a "${STATE_CONFIG}/credentials.db")" == 600 ]]
}
check "mode-only mismatches repair without sudo" mode_repair_without_sudo

state_symlink_protection() {
  local before output result=0
  mkdir -p "${work}/outside-state" "${work}/symlink-home"
  printf 'external-secret\n' >"${work}/outside-state/credentials.db"
  chmod 0644 "${work}/outside-state/credentials.db"
  before="$(stat -c %u:%g:%a "${work}/outside-state/credentials.db")"

  mv "${STATE_CONFIG}" "${STATE_CONFIG}.saved"
  ln -s "${work}/outside-state" "${STATE_CONFIG}"
  if output="$(HOME="${work}/symlink-home" "${INITIALIZE}" 2>&1)"; then result=1; fi
  [[ "${output}" == *"${STATE_CONFIG} is a symlink"* ]] || result=1
  if output="$(sudo "${INITIALIZE}" --repair "$(id -u)" "$(id -g)" 2>&1)"; then result=1; fi
  [[ "${output}" == *"${STATE_CONFIG} is a symlink"* ]] || result=1
  [[ "$(stat -c %u:%g:%a "${work}/outside-state/credentials.db")" == "${before}" ]] || result=1
  rm "${STATE_CONFIG}"
  mv "${STATE_CONFIG}.saved" "${STATE_CONFIG}"

  mv "${STATE_CONFIG}/credentials.db" "${STATE_CONFIG}/credentials.db.saved"
  ln -s "${work}/outside-state/credentials.db" "${STATE_CONFIG}/credentials.db"
  if output="$(HOME="${work}/symlink-home" "${INITIALIZE}" 2>&1)"; then result=1; fi
  [[ "${output}" == *"${STATE_CONFIG}/credentials.db is a symlink"* ]] || result=1
  if output="$(sudo "${INITIALIZE}" --repair "$(id -u)" "$(id -g)" 2>&1)"; then result=1; fi
  [[ "${output}" == *"${STATE_CONFIG}/credentials.db is a symlink"* ]] || result=1
  [[ "$(stat -c %u:%g:%a "${work}/outside-state/credentials.db")" == "${before}" ]] || result=1
  rm "${STATE_CONFIG}/credentials.db"
  mv "${STATE_CONFIG}/credentials.db.saved" "${STATE_CONFIG}/credentials.db"
  return "${result}"
}
check "state directory symlinks fail both normal and repair modes before touching external files" \
  state_symlink_protection

changed_uid_repair() {
  local before
  printf 'outside\n' >"${work}/external"
  chmod 0644 "${work}/external"
  sudo chown root:root "${work}/external"
  before="$(stat -c %u:%g:%a "${work}/external")"
  ln -s "${work}/external" "${STATE_CONFIG}/external-link"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  "${INITIALIZE}" || return 1
  rm "${STATE_CONFIG}/external-link"
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == "$(id -u):700" ]] \
    && [[ "$(stat -c %u:%a "${STATE_CONFIG}/credentials.db")" == "$(id -u):600" ]] \
    && [[ "$(stat -c %u:%g:%a "${work}/external")" == "${before}" ]]
}
check "a changed UID repairs state ownership and modes without modifying external symlink targets" changed_uid_repair

unavailable_repair() {
  local result=0
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  if PATH="${work}/no-sudo-modes:${PATH}" "${INITIALIZE}"; then result=1; fi
  [[ "$(sudo stat -c %u:%a "${STATE_DIR}")" == 23456:700 ]] || result=1
  sudo test -f "${STATE_CONFIG}/credentials.db" || result=1
  "${INITIALIZE}" || return 1
  return "${result}"
}
check "unavailable ownership repair fails without broadening access or deleting state" unavailable_repair

reportResults
