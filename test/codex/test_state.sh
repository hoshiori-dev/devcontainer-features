#!/usr/bin/env bash
# Exercises the real initializer and preserved configuration on the project's mounted state, using no account.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
readonly INITIALIZE="/usr/local/share/codex-feature/initialize"
readonly STATE_DIR="/var/lib/codex"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
"${INITIALIZE}"
check "initialization leaves absent Codex settings absent" test ! -e "${STATE_DIR}/config.toml"
install --mode 0600 /dev/null "${STATE_DIR}/config.toml"
cp "${STATE_DIR}/config.toml" "${work}/config.toml"

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

preserves_unrelated_settings() {
  printf '\nmodel_reasoning_effort = "low"\n' >>"${STATE_DIR}/config.toml"
  "${INITIALIZE}" || return 1
  grep -q 'model_reasoning_effort = "low"' "${STATE_DIR}/config.toml"
}
check "compatible TOML settings are preserved" preserves_unrelated_settings

preserves_backend() {
  local backend="$1"
  printf '# keep this comment\ncli_auth_credentials_store = "%s"\nmodel_reasoning_effort = "low"\n' "${backend}" \
    >"${STATE_DIR}/config.toml"
  cp "${STATE_DIR}/config.toml" "${work}/backend.toml"
  "${INITIALIZE}" || return 1
  cmp "${STATE_DIR}/config.toml" "${work}/backend.toml"
}
for backend in file auto keyring ephemeral; do
  check "initialization preserves ${backend} storage and all TOML content" preserves_backend "${backend}"
done
cp "${work}/config.toml" "${STATE_DIR}/config.toml"

without_cli() {
  mkdir "${work}/no-cli"
  printf '#!/bin/sh\nexit 91\n' >"${work}/no-cli/codex"
  chmod +x "${work}/no-cli/codex"
  PATH="${work}/no-cli:${PATH}" "${INITIALIZE}"
}
check "initialization does not require a Codex configuration service" without_cli

rejects_initialization() {
  local output
  if output="$("${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"codex: error:"* ]]
}
preserves_managed_policy() {
  sudo mkdir -p /etc/codex
  [[ ! -e /etc/codex/requirements.toml ]] || return 1
  printf 'cli_auth_credentials_store = "keyring"\n' >"${work}/requirements.toml"
  sudo cp "${work}/requirements.toml" /etc/codex/requirements.toml || return 1
  local result=0
  "${INITIALIZE}" || result=1
  cmp "${work}/requirements.toml" /etc/codex/requirements.toml || result=1
  cmp "${work}/config.toml" "${STATE_DIR}/config.toml" || result=1
  sudo rm /etc/codex/requirements.toml
  return "${result}"
}
check "managed keyring policy is preserved without rejecting initialization" preserves_managed_policy
check "explicit CODEX_HOME is rejected" env CODEX_HOME=/tmp/other-codex bash -c \
  'if /usr/local/share/codex-feature/initialize; then exit 1; fi'

home_conflicts() {
  local result=0
  mv "${HOME}/.codex" "${HOME}/.codex-test-link"
  mkdir "${HOME}/.codex"
  printf 'keep\n' >"${HOME}/.codex/marker"
  rejects_initialization || result=1
  [[ "$(cat "${HOME}/.codex/marker")" == keep ]] || result=1
  rm -r "${HOME}/.codex"
  ln -s /tmp/nonexistent-codex-home "${HOME}/.codex"
  rejects_initialization || result=1
  rm "${HOME}/.codex"
  mv "${HOME}/.codex-test-link" "${HOME}/.codex"
  return "${result}"
}
check "existing home directories and dangling links are preserved as conflicts" home_conflicts

new_home() {
  mkdir "${work}/home"
  HOME="${work}/home" "${INITIALIZE}" || return 1
  [[ "$(readlink -f "${work}/home/.codex")" == /var/lib/codex ]]
}
check "a different runtime home gets a missing link" new_home

private_credentials() {
  printf '%s\n' 'test-placeholder-not-a-real-key' | codex login --with-api-key >/dev/null 2>&1 || return 1
  [[ "$(stat -c %a "${STATE_DIR}/auth.json")" == 600 ]]
}
check "native file login stores a private cache without a model request" private_credentials
check "a fresh CLI process reads the saved credential cache" bash -c 'codex login status >/dev/null 2>&1'
check "the actual CLI saves a conversation using a loopback fixture" \
  node "$(dirname "$0")/session_fixture.mjs" create

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

replacement_preserves_state() {
  local user version
  user="$(id -un)"
  version="$(codex --version)"
  version="${version#codex-cli }"
  cp "${STATE_DIR}/auth.json" "${work}/auth.json"
  printf 'private fixture\n' >"${STATE_DIR}/state-fixture"
  sudo env PATH="${PATH}" VERSION=0.162.0 _REMOTE_USER="${user}" _REMOTE_USER_HOME="${HOME}" \
    bash "$(dirname "$0")/_feature/install.sh" || return 1
  [[ "$(codex --version)" == 'codex-cli 0.162.0' ]] || return 1
  sudo env PATH="${PATH}" VERSION="${version}" _REMOTE_USER="${user}" _REMOTE_USER_HOME="${HOME}" \
    bash "$(dirname "$0")/_feature/install.sh" || return 1
  [[ "$(codex --version)" == "codex-cli ${version}" ]] || return 1
  cmp "${STATE_DIR}/auth.json" "${work}/auth.json" || return 1
  [[ "$(cat "${STATE_DIR}/state-fixture")" == 'private fixture' ]]
}
check "replacement releases preserve credentials and runtime state" replacement_preserves_state
check "a new CLI process resumes saved history after ownership and release changes" \
  node "$(dirname "$0")/session_fixture.mjs" restore

# Both these locations are outside the feature's state mapping.
mkdir -p "${HOME}/.agents/skills/codex-test"
printf 'untouched\n' >"${HOME}/.agents/skills/codex-test/marker"
"${INITIALIZE}"
check "separate user skills remain unchanged" grep -q untouched "${HOME}/.agents/skills/codex-test/marker"
reportResults
