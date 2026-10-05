#!/usr/bin/env bash
# Scenario "non_default_options_debian": version 1.13.2, disableUpdateCheck false, and disableTelemetry true on
# debian:12, as root. Covers "Exact version", "Dependency released later", "Update check left to the user",
# "Telemetry disabled", and "Caller's telemetry value wins".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# lib.sh is next to this script in the workspace folder, which shellcheck does not see from where it runs.
# shellcheck source=/dev/null
source ./lib.sh

printf '%s\n' "Running as $(id -un)"

# Exact version.
check "openspec --version, run as the remote user, prints exactly 1.13.2" openspec_reports_version 1.13.2

# Requirement "Install the requested version".
check "the package installed as @fission-ai/openspec is at exactly the selected version, 1.13.2" \
  openspec_package_is_at 1.13.2
check "the package and every one of its dependencies were downloaded from ${REGISTRY}" all_from_registry

# Dependency released later. The publish times are read from the registry when the test runs, because the registry
# is their only record: no file of the installed tree holds them. publish_times.cjs exits 1 when an installed package
# was published after OpenSpec 1.13.2, and its report lists as "kept out:" each dependency that has a later release
# of the same major version, which an install without the bound could have taken.
report="$(mktemp)"
check "the installed version of every dependency is one the registry published no later than OpenSpec 1.13.2" \
  node ./publish_times.cjs "${PREFIX_DIR}" "${report}"
cat "${report}"
# The scenario's WHEN: a dependency has a release within upstream's range that the registry published after OpenSpec
# 1.13.2. Without one, the check above passes with or without the bound.
if ! grep -q '^kept out: ' "${report}"; then
  printf '%s\n' '"Dependency released later" is not shown: the report names no dependency with a later release in' \
    'range, so the check above passes without the bound too' >&2
  exit 1
fi
rm -f "${report}"

# Update check left to the user.
check "the openspec process sees OPENSPEC_NO_UPDATE_CHECK unset when the caller has not set it" \
  openspec_sees OPENSPEC_NO_UPDATE_CHECK unset -u OPENSPEC_NO_UPDATE_CHECK
check "the openspec process sees OPENSPEC_NO_UPDATE_CHECK exactly as the caller's environment has it" \
  openspec_sees OPENSPEC_NO_UPDATE_CHECK set:1 OPENSPEC_NO_UPDATE_CHECK=1

# Telemetry disabled.
check "with OPENSPEC_TELEMETRY unset, the openspec process sees OPENSPEC_TELEMETRY=0" \
  openspec_sees OPENSPEC_TELEMETRY set:0 -u OPENSPEC_TELEMETRY

# Caller's telemetry value wins.
check "with OPENSPEC_TELEMETRY=1 in the caller's environment, the openspec process sees OPENSPEC_TELEMETRY=1" \
  openspec_sees OPENSPEC_TELEMETRY set:1 OPENSPEC_TELEMETRY=1

reportResults
