#!/usr/bin/env bash
# Exercises the real initializer and real CLI writes on the mounted project state in a container without a network,
# using synthetic credential fixtures only; nothing signs in or reaches a model service.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# The scenario runner copies this helper beside the script; hooks may lint each script independently.
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"
readonly INITIALIZE="/usr/local/share/antigravity-feature/initialize"
readonly STATE_DIR="/var/lib/antigravity"
readonly ARCHIVE_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/9.9.9-1/linux-x64/cli.tar.gz"
readonly TOKEN="${HOME}/.gemini/antigravity-cli/antigravity-oauth-token"
readonly SECRETS="${HOME}/.config/antigravity/plugin-secrets.json"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
make_curl_stub "${work}/downloads"
"${INITIALIZE}"

# find and sudo both fail here, so a scan or a repair, which runs through sudo with its own PATH, fails the check.
healthy_without_scan() {
  local output
  mkdir "${work}/no-scan"
  printf '#!/bin/sh\nexit 91\n' >"${work}/no-scan/find"
  cp "${work}/no-scan/find" "${work}/no-scan/sudo"
  chmod +x "${work}/no-scan/find" "${work}/no-scan/sudo"
  output="$(PATH="${work}/no-scan:${PATH}" "${INITIALIZE}")" || return 1
  [[ "${output}" != *repairing* && "${output}" != *restoring* ]]
}
check "a healthy volume initializes without a full-tree scan or repair" healthy_without_scan
check "no start or attach hook is declared" jq -e '(has("postStartCommand") or has("postAttachCommand")) | not' \
  "$(dirname "$0")/_feature/devcontainer-feature.json"

missing_mount() {
  mkdir "${work}/missing-mount"
  printf '#!/bin/sh\nexit 1\n' >"${work}/missing-mount/mountpoint"
  chmod +x "${work}/missing-mount/mountpoint"
  if PATH="${work}/missing-mount:${PATH}" "${INITIALIZE}"; then return 1; fi
}
check "a missing state mount fails instead of using image storage" missing_mount

cli_writes_state() {
  timeout 60 agy mcp add --type http recreation-fixture http://127.0.0.1:9 >/dev/null || return 1
  timeout 60 agy agents >/dev/null || return 1
  [[ -f "${STATE_DIR}/gemini-config/mcp_config.json" && -f "${STATE_DIR}/cli/installation_id" \
    && -f "${STATE_DIR}/cli/jetski_state.pbtxt" && -L "${HOME}/.gemini/antigravity-cli" \
    && -L "${HOME}/.gemini/config" ]]
}
check "the real CLI saves configuration and replaced state files in the volume" cli_writes_state
check "the CLI's new state files are private" test "$(stat -c %a "${STATE_DIR}/gemini-config/mcp_config.json")" = 600
check "a fresh CLI process reads the saved configuration" bash -c 'agy mcp list | grep -q recreation-fixture'

# Writes synthetic file $1 the way an atomic writer does: a temporary sibling renamed over the target.
atomic_write() {
  printf 'synthetic %s fixture\n' "$2" >"$1.tmp"
  mv -f "$1.tmp" "$1"
}
atomic_credentials() {
  atomic_write "${TOKEN}" token-one
  atomic_write "${TOKEN}" token-two
  atomic_write "${SECRETS}" plugin-secret
  [[ "$(cat "${STATE_DIR}/cli/antigravity-oauth-token")" == 'synthetic token-two fixture' \
    && "$(cat "${STATE_DIR}/plugin-secrets/plugin-secrets.json")" == 'synthetic plugin-secret fixture' \
    && -L "${HOME}/.gemini/antigravity-cli" && -L "${HOME}/.config/antigravity" ]]
}
check "atomically replaced credential and plugin-secret fixtures stay volume-backed" atomic_credentials

private_without_printing() {
  local output
  output="$("${INITIALIZE}" 2>&1)" || return 1
  [[ "${output}" != *synthetic* \
    && "$(stat -c %a "${STATE_DIR}/cli/antigravity-oauth-token")" == 600 \
    && "$(stat -c %a "${STATE_DIR}/plugin-secrets/plugin-secrets.json")" == 600 ]]
}
check "initialization makes credential files private without printing them" private_without_printing

preserves_settings() {
  printf '{"fixture": "user settings"}\n' >"${STATE_DIR}/cli/settings.json"
  printf '{"fixture": "managed selection"}\n' >"${STATE_DIR}/gemini-config/config.json"
  cp "${STATE_DIR}/cli/settings.json" "${work}/settings.json"
  cp "${STATE_DIR}/gemini-config/config.json" "${work}/config.json"
  "${INITIALIZE}" || return 1
  cmp "${STATE_DIR}/cli/settings.json" "${work}/settings.json" \
    && cmp "${STATE_DIR}/gemini-config/config.json" "${work}/config.json"
}
check "initialization preserves user configuration byte for byte" preserves_settings

gemini_coexistence() {
  mkdir -p "${HOME}/.gemini/extensions/fixture"
  printf 'gemini fixture\n' >"${HOME}/.gemini/settings.json"
  printf 'extension fixture\n' >"${HOME}/.gemini/extensions/fixture/marker"
  "${INITIALIZE}" || return 1
  timeout 60 agy agents >/dev/null || return 1
  [[ "$(cat "${HOME}/.gemini/settings.json")" == 'gemini fixture' \
    && "$(cat "${HOME}/.gemini/extensions/fixture/marker")" == 'extension fixture' \
    && ! -L "${HOME}/.gemini" && ! -e "${STATE_DIR}/settings.json" && ! -e "${STATE_DIR}/extensions" ]]
}
check "unrelated Gemini data stays in place and out of the volume" gemini_coexistence

rejects_initialization() {
  local output
  if output="$("${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"antigravity: error:"* ]]
}
link_conflicts() {
  local link="${HOME}/.gemini/antigravity-cli"
  local result=0
  mv "${link}" "${work}/saved-link"
  mkdir "${link}"
  printf 'keep\n' >"${link}/marker"
  rejects_initialization || result=1
  [[ "$(cat "${link}/marker")" == keep ]] || result=1
  rm -r "${link}"
  printf 'keep\n' >"${link}"
  rejects_initialization || result=1
  rm "${link}"
  ln -s "${work}/nonexistent" "${link}"
  rejects_initialization || result=1
  rm "${link}"
  ln -s "${work}" "${link}"
  rejects_initialization || result=1
  rm "${link}"
  mv "${work}/saved-link" "${link}"
  [[ "$(cat "${STATE_DIR}/cli/antigravity-oauth-token")" == 'synthetic token-two fixture' ]] || result=1
  return "${result}"
}
check "existing directories, files, dangling links, and foreign links are preserved as conflicts" link_conflicts

new_home() {
  mkdir "${work}/home"
  HOME="${work}/home" XDG_CONFIG_HOME="" "${INITIALIZE}" || return 1
  [[ "$(readlink -f "${work}/home/.gemini/antigravity-cli")" == "${STATE_DIR}/cli" \
    && "$(cat "${work}/home/.gemini/antigravity-cli/antigravity-oauth-token")" == 'synthetic token-two fixture' ]]
}
check "a different runtime home gets the missing links and sees the saved state" new_home

xdg_root() {
  XDG_CONFIG_HOME="${work}/xdg" "${INITIALIZE}" || return 1
  [[ "$(readlink -f "${work}/xdg/antigravity")" == "${STATE_DIR}/plugin-secrets" ]]
}
check "the plugin-secret link follows the effective XDG_CONFIG_HOME" xdg_root
check "a relative XDG_CONFIG_HOME is rejected" env XDG_CONFIG_HOME=relative bash -c \
  'if /usr/local/share/antigravity-feature/initialize; then exit 1; fi'

mode_repair() {
  mkdir "${work}/no-sudo"
  printf '#!/bin/sh\nexit 1\n' >"${work}/no-sudo/sudo"
  chmod +x "${work}/no-sudo/sudo"
  chmod 0755 "${STATE_DIR}/cli"
  PATH="${work}/no-sudo:${PATH}" "${INITIALIZE}" || return 1
  [[ "$(stat -c %a "${STATE_DIR}/cli")" == 700 ]]
}
check "private modes are restored without privileged repair" mode_repair

state_link_conflicts() {
  local name file mode before output
  local result=0
  mkdir "${work}/link-home" "${work}/outside-state"
  printf 'synthetic external token fixture\n' >"${work}/outside-state/antigravity-oauth-token"
  printf 'synthetic external plugin fixture\n' >"${work}/outside-state/plugin-secrets.json"
  for name in cli plugin-secrets; do
    if [[ "${name}" == cli ]]; then file=antigravity-oauth-token; else file=plugin-secrets.json; fi
    mv "${STATE_DIR}/${name}" "${STATE_DIR}/${name}.saved"
    ln -s "${work}/outside-state" "${STATE_DIR}/${name}"
    # Both entry points must reject the intermediate link before changing external modes or ownership.
    for mode in normal repair; do
      chmod 0644 "${work}/outside-state/${file}"
      before="$(stat -c %u:%g:%a "${work}/outside-state/${file}")"
      if [[ "${mode}" == normal ]]; then
        if output="$(HOME="${work}/link-home" XDG_CONFIG_HOME="" "${INITIALIZE}" 2>&1)"; then result=1; fi
      else
        if output="$(sudo "${INITIALIZE}" --repair "$(id -u)" "$(id -g)" 2>&1)"; then result=1; fi
      fi
      [[ "${output}" == *"${STATE_DIR}/${name} is a symlink"* ]] || result=1
      [[ "$(stat -c %u:%g:%a "${work}/outside-state/${file}")" == "${before}" ]] || result=1
    done
    rm "${STATE_DIR}/${name}"
    mv "${STATE_DIR}/${name}.saved" "${STATE_DIR}/${name}"
  done
  return "${result}"
}
check "state directory links fail before normal or root repair changes external credentials" state_link_conflicts

changed_uid() {
  printf 'outside\n' >"${work}/external"
  chmod 0644 "${work}/external"
  # Owned by neither the remote user nor the fake UID, so a repair that follows the link changes it visibly.
  sudo chown root:root "${work}/external"
  local before
  before="$(stat -c %u:%g:%a "${work}/external")"
  ln -s "${work}/external" "${STATE_DIR}/cli/external-link"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  "${INITIALIZE}" || return 1
  rm "${STATE_DIR}/cli/external-link"
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == "$(id -u):700" \
    && "$(stat -c %u:%a "${STATE_DIR}/cli/antigravity-oauth-token")" == "$(id -u):600" \
    && "$(stat -c %u:%g:%a "${work}/external")" == "${before}" ]]
}
check "a changed UID is repaired without changing external link targets" changed_uid

unavailable_repair() {
  local result=0
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  if PATH="${work}/no-sudo:${PATH}" "${INITIALIZE}"; then result=1; fi
  [[ "$(sudo stat -c %u:%a "${STATE_DIR}")" == 23456:700 ]] || result=1
  sudo test -f "${STATE_DIR}/cli/antigravity-oauth-token" || result=1
  "${INITIALIZE}" || return 1
  return "${result}"
}
check "unavailable repair fails without broadening access or deleting state" unavailable_repair

profiles_digest() {
  cat "${HOME}/.bashrc" "${HOME}/.profile" 2>/dev/null | sha256sum
}
release_changes() {
  local current profiles inode
  current="$(agy --version)"
  profiles="$(profiles_digest)"
  cp "${STATE_DIR}/gemini-config/mcp_config.json" "${work}/mcp_config.json"
  mkdir "${work}/real"
  cp /usr/local/share/antigravity/agy "${work}/real/antigravity"
  tar -czf "${work}/real.tar.gz" -C "${work}/real" antigravity
  make_archive "${work}/new.tar.gz" 'echo 9.9.9'
  make_manifest "${work}/new.json" 9.9.9 "${ARCHIVE_URL}" "${work}/new.tar.gz"
  make_manifest "${work}/real.json" "${current}" "${ARCHIVE_URL}" "${work}/real.tar.gz"
  run_install "${work}/downloads" "${work}/new.json" "${work}/new.tar.gz"
  succeeded && [[ "$(agy --version)" == 9.9.9 ]] || return 1
  run_install "${work}/downloads" "${work}/real.json" "${work}/real.tar.gz"
  succeeded && [[ "$(agy --version)" == "${current}" ]] || return 1
  inode="$(stat -c %i /usr/local/share/antigravity/agy)"
  run_install "${work}/downloads" "${work}/real.json" "${work}/real.tar.gz"
  succeeded "is already installed" && [[ "$(stat -c %i /usr/local/share/antigravity/agy)" == "${inode}" ]] || return 1
  [[ "$(profiles_digest)" == "${profiles}" ]] || return 1
  cmp "${STATE_DIR}/gemini-config/mcp_config.json" "${work}/mcp_config.json" \
    && [[ "$(cat "${TOKEN}")" == 'synthetic token-two fixture' ]]
}
check "a changed release replaces the CLI, an unchanged one is kept, and state and profiles stay intact" \
  release_changes
check "a fresh CLI process reads saved configuration after ownership and release changes" \
  bash -c 'agy mcp list | grep -q recreation-fixture'
reportResults
