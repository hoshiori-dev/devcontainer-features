# shellcheck shell=bash
# Body of the scenarios "non_default_options_ubuntu" and "non_default_options_debian": version
# 1.13.2, disableUpdateCheck false, disableTelemetry true. Covers "Exact version", "Dependency
# released later", "Update check left to the user", "Telemetry disabled", and "Caller's telemetry
# value wins".
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source ./lib.sh

echo "Running as $(id -un)"

# Exact version.
check "openspec --version prints exactly 1.13.2" [ "$(openspec --version)" = 1.13.2 ]
check "the installed package is at 1.13.2" [ "$(installed_version)" = 1.13.2 ]
check "every package came from the public npm registry" all_from_registry

# Dependency released later: publish_times.cjs asks the registry for the publish time of every
# installed package and lists the dependencies that have a later release of the same major.
report=$(mktemp)
check "no installed package was published after OpenSpec 1.13.2" node ./publish_times.cjs "$PREFIX_DIR" "$report"
cat "$report"
check "a dependency has a later release, which the bound kept out" grep -q '^kept out: ' "$report"
rm -f "$report"

# Update check left to the user, Telemetry disabled, Caller's telemetry value wins.
check "with both variables unset, openspec sees telemetry off and the update check untouched" \
  [ "$(seen_env -u OPENSPEC_NO_UPDATE_CHECK -u OPENSPEC_TELEMETRY)" = "NO_UPDATE_CHECK=unset TELEMETRY=set:0" ]
check "the caller's OPENSPEC_NO_UPDATE_CHECK is passed through" \
  [ "$(seen_env -u OPENSPEC_TELEMETRY OPENSPEC_NO_UPDATE_CHECK=1)" = "NO_UPDATE_CHECK=set:1 TELEMETRY=set:0" ]
check "the caller's OPENSPEC_TELEMETRY=1 is kept" \
  [ "$(seen_env -u OPENSPEC_NO_UPDATE_CHECK OPENSPEC_TELEMETRY=1)" = "NO_UPDATE_CHECK=unset TELEMETRY=set:1" ]

reportResults
