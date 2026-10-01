# shellcheck shell=bash
# Body of the scenarios "node_switched_ubuntu" and "node_switched_debian": the default options
# written out (version latest, disableUpdateCheck true, disableTelemetry false). Covers "Update
# check disabled", "Caller's update-check value wins", "Telemetry left to the user", and "Current
# Node.js switched later".
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source ./lib.sh

# A Node.js older than OpenSpec requires, so openspec could not run on it.
OTHER_NODE=18

# Installs Node.js $1 with nvm and makes it the default and the current one, as the remote user.
switch_node() (
  set +e
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install "$1" && nvm alias default "$1" && nvm use default
)

echo "Running as $(id -un)"
latest=$(registry_latest)
check "openspec --version prints the registry's latest version ($latest)" [ "$(openspec --version)" = "$latest" ]

# Update check disabled, Caller's update-check value wins, Telemetry left to the user.
check "with both variables unset, openspec sees the update check off and telemetry untouched" \
  [ "$(seen_env -u OPENSPEC_NO_UPDATE_CHECK -u OPENSPEC_TELEMETRY)" = "NO_UPDATE_CHECK=set:1 TELEMETRY=unset" ]
check "the caller's empty OPENSPEC_NO_UPDATE_CHECK is kept" \
  [ "$(seen_env -u OPENSPEC_TELEMETRY OPENSPEC_NO_UPDATE_CHECK=)" = "NO_UPDATE_CHECK=set: TELEMETRY=unset" ]
check "the caller's OPENSPEC_TELEMETRY=0 is passed through" \
  [ "$(seen_env -u OPENSPEC_NO_UPDATE_CHECK OPENSPEC_TELEMETRY=0)" = "NO_UPDATE_CHECK=set:1 TELEMETRY=set:0" ]

# Current Node.js switched later.
installed_node=$(seen_node)
echo "openspec runs on $installed_node"
check "openspec runs on the Node.js that is current after the build" \
  [ "$installed_node" = "$(readlink -f "$(command -v node)")" ]
check "nvm installs Node.js $OTHER_NODE and makes it the default" switch_node "$OTHER_NODE"
check "the current Node.js is now $OTHER_NODE" [ "$(node --version | cut -d. -f1)" = "v$OTHER_NODE" ]
check "the Node.js on PATH is no longer the one openspec was installed with" \
  [ "$(readlink -f "$(command -v node)")" != "$installed_node" ]
check "openspec --version still prints $latest" [ "$(openspec --version)" = "$latest" ]
check "openspec still runs on the Node.js it was installed with" [ "$(seen_node)" = "$installed_node" ]

reportResults
