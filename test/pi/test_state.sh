#!/usr/bin/env bash
# Exercises the initializer and the real CLI on the mounted project state with synthetic fixtures only: no login, no
# real key, no package manager, and no model request.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/pi-feature/initialize"
readonly STATE_DIR="/var/lib/pi"
readonly AGENT_DIR="/var/lib/pi/agent"
readonly PROJECT="/tmp/pi-session-fixture"
# Pi keeps a working directory's sessions in a folder named after its path, "/" replaced by "-", between "--".
readonly SESSION_PATH="sessions/--tmp-pi-session-fixture--/2026-10-23T00-00-00-000Z_fixture-session.jsonl"
FIXTURES="$(cd "$(dirname "$0")" && pwd)"
readonly FIXTURES
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${PROJECT}"

"${INITIALIZE}"

# Sends the RPC command $1 to a fresh Pi process in the fixture project, with extra CLI arguments $2...
rpc() {
  local command="$1"
  shift
  (cd "${PROJECT}" && printf '%s\n' "${command}" | timeout 60 pi --offline --mode rpc "$@")
}

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
  [[ "${output}" == *"pi: error:"* ]]
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

stores_credential() {
  install -m 0600 "${FIXTURES}/auth_fixture.json" "${HOME}/.pi/agent/.auth.json.next"
  mv "${HOME}/.pi/agent/.auth.json.next" "${HOME}/.pi/agent/auth.json"
  cmp "${FIXTURES}/auth_fixture.json" "${AGENT_DIR}/auth.json" \
    && [[ "$(stat -c %a "${AGENT_DIR}/auth.json")" == 600 ]]
}
check "an atomically replaced synthetic credential is stored privately in the volume" stores_credential
# Prints ready when Pi resolves a credential for provider $1 from the default agent directory, without printing it.
credential_ready() { [[ "$(cd "${PROJECT}" && pi auth check --provider "$1" --no-refresh)" == ready ]]; }
check "a fresh CLI process reads the stored credential" credential_ready anthropic
# The fixture's command-backed openai entry stands for a credential backend the user selected; only its preservation
# is checked, not whether it resolves.
initialization_keeps_credentials() {
  local output
  output="$("${INITIALIZE}" 2>&1)" || return 1
  [[ "${output}" != *test-placeholder* ]] && cmp "${FIXTURES}/auth_fixture.json" "${AGENT_DIR}/auth.json"
}
check "initialization keeps the user's credential choices and prints no credential" initialization_keeps_credentials

# A local package with one skill: pi install records its path in settings.json and does not copy it.
mkdir -p "${work}/local-package/skills/local-skill"
printf '{"name":"pi-local-fixture","version":"1.0.0","keywords":["pi-package"]}\n' \
  >"${work}/local-package/package.json"
printf -- '---\nname: local-skill\ndescription: Synthetic local fixture skill.\n---\nNothing to do.\n' \
  >"${work}/local-package/skills/local-skill/SKILL.md"
saves_settings() {
  (cd "${PROJECT}" && pi install "${work}/local-package" >/dev/null) || return 1
  grep -q local-package "${AGENT_DIR}/settings.json"
}
check "pi install saves the package declaration in the volume" saves_settings

# A package laid out as npm installs it in the agent's npm directory, declared through an atomically replaced
# settings.json; no package manager runs.
seeded_package_listed() {
  local package="${HOME}/.pi/agent/npm/node_modules/pi-npm-fixture" listed
  mkdir -p "${package}/skills/npm-skill"
  printf '{"name":"pi-npm-fixture","version":"1.0.0","keywords":["pi-package"]}\n' >"${package}/package.json"
  printf -- '---\nname: npm-skill\ndescription: Synthetic npm fixture skill.\n---\nNothing to do.\n' \
    >"${package}/skills/npm-skill/SKILL.md"
  jq '.packages += ["npm:pi-npm-fixture@1.0.0"]' "${HOME}/.pi/agent/settings.json" >"${work}/settings.json"
  cp "${work}/settings.json" "${HOME}/.pi/agent/.settings.json.next"
  mv "${HOME}/.pi/agent/.settings.json.next" "${HOME}/.pi/agent/settings.json"
  [[ -f "${AGENT_DIR}/npm/node_modules/pi-npm-fixture/package.json" ]] || return 1
  listed="$(cd "${PROJECT}" && pi list)"
  [[ "${listed}" == *"${HOME}/.pi/agent/npm/node_modules/pi-npm-fixture"* && "${listed}" == *local-package* ]]
}
check "a replaced configuration and a package in the agent's npm directory stay in the volume" seeded_package_listed

mkdir -p "${HOME}/.pi/agent/skills/user-skill"
printf -- '---\nname: user-skill\ndescription: Synthetic user fixture skill.\n---\nNothing to do.\n' \
  >"${HOME}/.pi/agent/skills/user-skill/SKILL.md"
loads_skills() {
  local output
  [[ -f "${AGENT_DIR}/skills/user-skill/SKILL.md" ]] || return 1
  output="$(rpc '{"type":"get_commands"}' --no-session)"
  [[ "${output}" == *'"skill:user-skill"'* && "${output}" == *'"skill:npm-skill"'* \
    && "${output}" == *'"skill:local-skill"'* ]]
}
check "a fresh CLI process loads the user skill and both packages' skills from the volume" loads_skills

npm_missing_reported() {
  local output
  if command -v npm >/dev/null; then return 1; fi
  if output="$(cd "${PROJECT}" && pi install npm:pi-unavailable-fixture 2>&1)"; then return 1; fi
  [[ "${output}" == *"Executable not found in"*npm* ]] || { printf '%s\n' "${output}"; return 1; }
  cmp "${work}/settings.json" "${AGENT_DIR}/settings.json" && credential_ready anthropic
}
check "pi install from npm without npm reports the missing executable and the CLI stays usable" npm_missing_reported

saves_session() {
  mkdir -p "$(dirname "${HOME}/.pi/agent/${SESSION_PATH}")"
  cp "${FIXTURES}/session_fixture.jsonl" "${HOME}/.pi/agent/${SESSION_PATH}"
  rpc '{"type":"set_session_name","name":"synthetic fixture name"}' --session-id fixture-session >/dev/null \
    || return 1
  grep -q '"name":"synthetic fixture name"' "${AGENT_DIR}/${SESSION_PATH}"
}
check "the CLI saves to a synthetic session in the volume" saves_session
reopens_session() {
  local output
  output="$(rpc '{"type":"get_entries"}' --session fixture-session)"
  [[ "${output}" == *"synthetic fixture message"* && "${output}" == *"synthetic fixture name"* ]]
}
check "a fresh CLI process reopens the saved session" reopens_session
# Pi creates session directories with the caller's umask; the private state root keeps other users out regardless.
check "another user cannot read the session Pi saved" \
  sudo setpriv --reuid=nobody --regid=nogroup --clear-groups test ! -r "${AGENT_DIR}/${SESSION_PATH}"

initialization_keeps_configuration() {
  cp "${AGENT_DIR}/settings.json" "${work}/settings-before.json"
  "${INITIALIZE}" || return 1
  [[ -L "${HOME}/.pi/agent" ]] && cmp "${work}/settings-before.json" "${AGENT_DIR}/settings.json"
}
check "initialization keeps the saved configuration" initialization_keeps_configuration

# Runs the initializer with a conflicting entry at ~/.pi/agent and restores the real link afterwards.
conflict_preserved() {
  local kind="$1" path="${HOME}/.pi/agent" result=0
  mv "${path}" "${work}/agent-link"
  case "${kind}" in
    file) printf 'keep\n' >"${path}" ;;
    directory) mkdir "${path}" && printf 'keep\n' >"${path}/marker" ;;
    dangling) ln -s /tmp/pi-missing-target "${path}" ;;
    foreign) mkdir "${work}/foreign" && ln -s "${work}/foreign" "${path}" ;;
  esac
  rejects_initialization || result=1
  case "${kind}" in
    file) [[ "$(cat "${path}")" == keep ]] || result=1 ;;
    directory) [[ "$(cat "${path}/marker")" == keep ]] || result=1 ;;
    dangling) [[ "$(readlink "${path}")" == /tmp/pi-missing-target ]] || result=1 ;;
    foreign) [[ "$(readlink "${path}")" == "${work}/foreign" ]] || result=1 ;;
  esac
  rm -r "${path}"
  mv "${work}/agent-link" "${path}"
  cmp "${FIXTURES}/auth_fixture.json" "${AGENT_DIR}/auth.json" || result=1
  return "${result}"
}
for kind in file directory dangling foreign; do
  check "an existing ${kind} at ~/.pi/agent is reported and preserved" conflict_preserved "${kind}"
done

new_home() {
  mkdir -p "${work}/home/.pi"
  printf 'other\n' >"${work}/home/.pi/other-file"
  HOME="${work}/home" "${INITIALIZE}" || return 1
  [[ "$(readlink "${work}/home/.pi/agent")" == "${AGENT_DIR}" && "$(cat "${work}/home/.pi/other-file")" == other ]] \
    || return 1
  [[ "$(cd "${PROJECT}" && HOME="${work}/home" pi auth check --provider anthropic --no-refresh)" == ready ]]
}
check "a different runtime home gets its link, keeps its other files, and reaches the same state" new_home

dangling_parent_rejected() {
  local output
  mkdir "${work}/dangling-home"
  ln -s /tmp/pi-missing-parent "${work}/dangling-home/.pi"
  if output="$(HOME="${work}/dangling-home" "${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"pi: error: ${work}/dangling-home/.pi is not a directory;"* \
    && "$(readlink "${work}/dangling-home/.pi")" == /tmp/pi-missing-parent ]]
}
check "a dangling .pi link in the home is reported and preserved" dangling_parent_rejected

home_inside_volume_rejected() {
  local output result=0
  mkdir "${AGENT_DIR}/home-inside"
  if output="$(HOME="${AGENT_DIR}/home-inside" "${INITIALIZE}" 2>&1)"; then result=1; fi
  [[ "${output}" == *"lies inside ${STATE_DIR};"* && ! -e "${AGENT_DIR}/home-inside/.pi" ]] || result=1
  rmdir "${AGENT_DIR}/home-inside"
  return "${result}"
}
check "a home inside the state volume is rejected before any link is created" home_inside_volume_rejected

agent_dir_variable_rejected() {
  local output
  if output="$(PI_CODING_AGENT_DIR="${work}/elsewhere" "${INITIALIZE}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"pi: error: PI_CODING_AGENT_DIR is set;"* && ! -e "${work}/elsewhere" ]] \
    && cmp "${FIXTURES}/auth_fixture.json" "${AGENT_DIR}/auth.json"
}
check "a caller-provided PI_CODING_AGENT_DIR is reported without changing state" agent_dir_variable_rejected

private_credentials_repaired() {
  printf '{}\n' >"${HOME}/.pi/agent/mcp-auth.json"
  chmod 0644 "${AGENT_DIR}/auth.json" "${AGENT_DIR}/mcp-auth.json"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %a "${AGENT_DIR}/auth.json")" == 600 && "$(stat -c %a "${AGENT_DIR}/mcp-auth.json")" == 600 ]]
}
check "readable credential files are made private again" private_credentials_repaired
setgid_directory_repaired() {
  chmod g+s "${AGENT_DIR}"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %a "${AGENT_DIR}")" == 700 ]]
}
check "a set-group-ID agent directory is repaired to mode 0700" setgid_directory_repaired

linked_store_untouched() {
  local result=0
  mv "${AGENT_DIR}/mcp-auth.json" "${work}/mcp-auth.json"
  printf '{}\n' >"${work}/external-store.json"
  chmod 0640 "${work}/external-store.json"
  ln -s "${work}/external-store.json" "${HOME}/.pi/agent/mcp-auth.json"
  "${INITIALIZE}" || result=1
  [[ "$(stat -c %a "${work}/external-store.json")" == 640 ]] || result=1
  rm "${AGENT_DIR}/mcp-auth.json"
  mv "${work}/mcp-auth.json" "${AGENT_DIR}/mcp-auth.json"
  return "${result}"
}
check "a credential file linked to a store the user chose is neither followed nor rejected" linked_store_untouched

changed_uid() {
  local before
  printf 'outside\n' >"${work}/external"
  chmod 0644 "${work}/external"
  # Owned by neither the remote user nor the fake UID, so a repair that follows the link changes it visibly.
  sudo chown root:root "${work}/external"
  before="$(stat -c %u:%g:%a "${work}/external")"
  ln -s "${work}/external" "${AGENT_DIR}/external-link"
  sudo chown -R -h 23456:23456 "${STATE_DIR}"
  "${INITIALIZE}" || return 1
  [[ "$(stat -c %u:%a "${STATE_DIR}")" == "$(id -u):700" \
    && "$(stat -c %u:%a "${AGENT_DIR}/auth.json")" == "$(id -u):600" \
    && "$(stat -c %u:%g:%a "${work}/external")" == "${before}" ]] || return 1
  rm "${AGENT_DIR}/external-link"
  credential_ready anthropic
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
  sudo test -f "${AGENT_DIR}/auth.json" || result=1
  "${INITIALIZE}" || return 1
  return "${result}"
}
check "unavailable repair fails without broadening access or deleting state" unavailable_repair

same_release_skipped() {
  local current before output
  current="$(pi --version)"
  before="$(stat -c %i:%Y /usr/local/lib/pi/pi)"
  output="$(sudo env PATH="${PATH}" VERSION="${current}" _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${FIXTURES}/_feature/install.sh")" || return 1
  [[ "${output}" == *"is already installed at /usr/local/lib/pi"* \
    && "$(stat -c %i:%Y /usr/local/lib/pi/pi)" == "${before}" ]] || return 1
  credential_ready anthropic && reopens_session
}
check "installing the same release again skips the replacement and keeps state" same_release_skipped
replacement_keeps_state() {
  local current
  current="$(pi --version)"
  sudo env PATH="${PATH}" VERSION=1.4.0 _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${FIXTURES}/_feature/install.sh" || return 1
  [[ "$(pi --version)" == 1.4.0 ]] || return 1
  sudo env PATH="${PATH}" VERSION="${current}" _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${FIXTURES}/_feature/install.sh" || return 1
  [[ "$(pi --version)" == "${current}" ]] || return 1
  credential_ready anthropic && reopens_session && [[ "$(cd "${PROJECT}" && pi list)" == *pi-npm-fixture* ]]
}
check "another release replaces the CLI and keeps credentials, sessions, and configuration" replacement_keeps_state
reportResults
