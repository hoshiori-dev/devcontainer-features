#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
readonly STATE_DIR=/var/lib/claude-code
readonly INITIALIZE=/usr/local/share/claude-code-feature/initialize
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
expected="${EXPECTED_CLAUDE_VERSION:-2.1.89}"
if [[ "${expected}" == latest ]]; then
  expected="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location \
    https://downloads.claude.ai/claude-code-releases/latest)"
fi
check "the selected native release is installed" test "$(claude --version)" = "${expected} (Claude Code)"
"${INITIALIZE}"
printf '{}\n' >"${STATE_DIR}/settings.json"
cp "${STATE_DIR}/settings.json" "${work}/settings"
printf '{"fixture":"not-a-real-credential"}\n' >"${STATE_DIR}/.credentials.json"
chmod 0600 "${STATE_DIR}/.credentials.json"
cp "${STATE_DIR}/.credentials.json" "${work}/credentials"
claude mcp add --scope user --transport http persistence-fixture http://127.0.0.1:9 >/dev/null
check "actual CLI configuration writes stay in the volume" test -f "${STATE_DIR}/.claude.json"
check "a fresh CLI reads saved configuration without login" bash -c \
  'claude mcp get persistence-fixture >/dev/null'
claude mcp remove --scope user persistence-fixture >/dev/null
check "atomic configuration replacement stays volume-backed" test -f "${STATE_DIR}/.claude.json"
"${INITIALIZE}"
check "initialization preserves credential fixture contents" cmp "${STATE_DIR}/.credentials.json" "${work}/credentials"
check "credential files stay private" test "$(stat -c %a "${STATE_DIR}/.credentials.json")" = 600
check "caller configuration overrides are preserved as conflicts" bash -c \
  'if CLAUDE_CONFIG_DIR=/tmp/other /usr/local/share/claude-code-feature/initialize; then exit 1; fi'
rejects_initialization() {
  if "${INITIALIZE}"; then return 1; fi
}
healthy_without_scan() {
  mkdir "${work}/bin"
  printf '#!/bin/sh\nexit 91\n' >"${work}/bin/find"
  chmod +x "${work}/bin/find"
  PATH="${work}/bin:${PATH}" "${INITIALIZE}"
}
check "healthy volumes initialize without a full-tree scan" healthy_without_scan

missing_mount() {
  mkdir "${work}/missing-mount"
  printf '#!/bin/sh\nexit 1\n' >"${work}/missing-mount/mountpoint"
  chmod +x "${work}/missing-mount/mountpoint"
  if PATH="${work}/missing-mount:${PATH}" "${INITIALIZE}"; then return 1; fi
}
check "a missing mount is rejected rather than treated as persistent storage" missing_mount

home_conflicts() {
  local result=0
  mv "${HOME}/.claude" "${HOME}/.claude-test-link"
  mkdir "${HOME}/.claude"
  printf 'keep\n' >"${HOME}/.claude/marker"
  rejects_initialization || result=1
  [[ "$(cat "${HOME}/.claude/marker")" == keep ]] || result=1
  rm -r "${HOME}/.claude"
  ln -s /tmp/nonexistent-claude-home "${HOME}/.claude"
  rejects_initialization || result=1
  rm "${HOME}/.claude"
  mv "${HOME}/.claude-test-link" "${HOME}/.claude"
  return "${result}"
}
check "existing home directories and dangling links are preserved as conflicts" home_conflicts

global_config_conflict() {
  printf 'preserve global configuration\n' >"${HOME}/.claude.json"
  local result=0
  rejects_initialization || result=1
  [[ "$(cat "${HOME}/.claude.json")" == 'preserve global configuration' ]] || result=1
  rm "${HOME}/.claude.json"
  return "${result}"
}
check "existing global configuration is preserved as a conflict" global_config_conflict

new_home() {
  mkdir "${work}/home"
  HOME="${work}/home" "${INITIALIZE}" || return 1
  [[ "$(readlink -f "${work}/home/.claude")" == /var/lib/claude-code ]]
}
check "a different runtime home gets a missing link" new_home

changed_uid() {
  printf 'outside\n' >"${work}/external"
  chmod 0644 "${work}/external"
  local before
  before="$(stat -c %u:%g:%a "${work}/external")"
  ln -s "${work}/external" "${STATE_DIR}/external-link"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == "$(id -u):700" \
    && "$(stat -c %u:%g:%a "${work}/external")" == "${before}" ]]
}
check "changed UID is repaired without changing external symlink targets" changed_uid

unavailable_repair() {
  mkdir "${work}/no-sudo"
  printf '#!/bin/sh\nexit 1\n' >"${work}/no-sudo/sudo"
  chmod +x "${work}/no-sudo/sudo"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  local result=0
  if PATH="${work}/no-sudo:${PATH}" "${INITIALIZE}"; then result=1; fi
  [[ "$(stat -c %u "${STATE_DIR}")" == 23456 ]] || result=1
  "${INITIALIZE}" || return 1
  return "${result}"
}
check "unavailable repair fails without broadening permissions or deleting state" unavailable_repair

sudo env VERSION="${expected}" _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
  bash "$(dirname "$0")/_feature/install.sh"
"${INITIALIZE}"
check "reinstallation preserves credential fixture contents" cmp "${STATE_DIR}/.credentials.json" "${work}/credentials"
check "initialization and reinstallation preserve user settings" cmp "${STATE_DIR}/settings.json" "${work}/settings"

reportResults
