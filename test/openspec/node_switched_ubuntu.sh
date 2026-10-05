#!/usr/bin/env bash
# Scenario "node_switched_ubuntu": the default options written out (version latest, disableUpdateCheck true,
# disableTelemetry false) on mcr.microsoft.com/devcontainers/base:ubuntu24.04, as vscode, who then makes a second
# Node.js the current one with nvm. Covers "Omitted version" with version latest, "Update check disabled", "Caller's
# update-check value wins", "Telemetry left to the user", and "Current Node.js switched later".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# lib.sh is next to this script in the workspace folder, which shellcheck does not see from where it runs.
# shellcheck source=/dev/null
source ./lib.sh

# A Node.js older than OpenSpec requires, so openspec could not run on it.
readonly OTHER_NODE=18

# The version the registry names as latest when the test runs; a release between build and test fails once.
latest="$(
  node -e '
    fetch(process.argv[1], { redirect: "error" })
      .then((response) => response.json())
      .then((document) => console.log(document["dist-tags"].latest));
  ' "${REGISTRY}@fission-ai%2fopenspec"
)"
printf '%s\n' "Expecting OpenSpec ${latest}, as $(id -un)"

# Prints the Node.js binary that nvm's `current` link names. A shell that loaded nvm before the switch, as the one
# this script runs in may have, keeps the first Node.js's own directory on PATH, so what is current is read from the
# link, not from PATH.
current_node() {
  readlink -f "${NVM_DIR}/current/bin/node"
}

# Installs Node.js $1 with nvm and makes it the default and the current one, as the remote user would. A subshell,
# so that the functions and the PATH nvm.sh brings stay out of this script. errexit and nounset stay on: nvm turns
# errexit off for its own commands.
switch_node() (
  # nvm.sh belongs to the image, not to this repository.
  # shellcheck source=/dev/null
  source "${NVM_DIR}/nvm.sh"
  nvm install "$1" && nvm alias default "$1" && nvm use default
)

# Omitted version, with version set to latest.
check "openspec --version, run as the remote user, prints the version the registry names as latest" \
  openspec_reports_version "${latest}"

# Update check disabled.
check "with OPENSPEC_NO_UPDATE_CHECK unset, the openspec process sees OPENSPEC_NO_UPDATE_CHECK=1" \
  openspec_sees OPENSPEC_NO_UPDATE_CHECK set:1 -u OPENSPEC_NO_UPDATE_CHECK

# Caller's update-check value wins.
check "with OPENSPEC_NO_UPDATE_CHECK set to the empty string, the openspec process sees it set to the empty string" \
  openspec_sees OPENSPEC_NO_UPDATE_CHECK set: OPENSPEC_NO_UPDATE_CHECK=

# Telemetry left to the user.
check "the openspec process sees OPENSPEC_TELEMETRY unset when the caller has not set it" \
  openspec_sees OPENSPEC_TELEMETRY unset -u OPENSPEC_TELEMETRY
check "the openspec process sees OPENSPEC_TELEMETRY exactly as the caller's environment has it" \
  openspec_sees OPENSPEC_TELEMETRY set:0 OPENSPEC_TELEMETRY=0

# Requirement "Run on a supported Node.js". The Node.js found on PATH when the feature was installed is the one nvm's
# `current` link names until the switch below. Its path is read here, not written as a literal: it holds the version
# the Node.js feature's `lts` named when the image was built.
installed_node="$(current_node)"
check "openspec runs on the Node.js found on PATH when the feature was installed" openspec_runs_on "${installed_node}"

# Current Node.js switched later. Setup: the remote user makes a different installed Node.js the current one.
switch_node "${OTHER_NODE}"
switched_node="$(current_node)"
switched_version="$("${switched_node}" --version)"
printf '%s\n' "nvm's current Node.js is now ${switched_version} (${switched_node})"
if [[ "${switched_version}" != "v${OTHER_NODE}."* ]]; then
  printf '%s\n' "\"Current Node.js switched later\" would not run: nvm's current Node.js is not ${OTHER_NODE}" >&2
  exit 1
fi
if [[ "${switched_node}" == "${installed_node}" ]]; then
  printf '%s\n' '"Current Node.js switched later" would not run: the current Node.js is still the one openspec was' \
    'installed with' >&2
  exit 1
fi

check "openspec --version still prints the installed version" openspec_reports_version "${latest}"
# The current Node.js comes first on PATH in every shell the remote user starts after the switch.
check "openspec --version still prints the installed version with the current Node.js first on PATH" \
  openspec_reports_version "${latest}" "PATH=${NVM_DIR}/current/bin:${PATH}"
check "openspec still runs on the Node.js it was installed with" openspec_runs_on "${installed_node}"

reportResults
