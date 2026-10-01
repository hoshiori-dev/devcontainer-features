#!/usr/bin/env bash
# Install-twice test ("Different options the second time"): openspec is installed first with
# non-default options (the proposal 1.13.1, disableUpdateCheck false, disableTelemetry true), then
# with the defaults. The first install's values arrive as VERSION, DISABLEUPDATECHECK, and
# DISABLETELEMETRY, the second's as VERSION__DEFAULT, DISABLEUPDATECHECK__DEFAULT, and
# DISABLETELEMETRY__DEFAULT.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source ./lib.sh

echo "First install: version=${VERSION:-} disableUpdateCheck=${DISABLEUPDATECHECK:-}" \
  "disableTelemetry=${DISABLETELEMETRY:-}"
echo "Second install: version=${VERSION__DEFAULT:-} disableUpdateCheck=${DISABLEUPDATECHECK__DEFAULT:-}" \
  "disableTelemetry=${DISABLETELEMETRY__DEFAULT:-}"

second=${VERSION__DEFAULT:-latest}
if [ "$second" = latest ]; then
  second=$(registry_latest)
fi
check "the two installs name different versions" [ "${VERSION:-}" != "$second" ]
check "openspec --version prints the second install's version" [ "$(openspec --version)" = "$second" ]

# The environment the second install's options define.
expected="NO_UPDATE_CHECK=unset"
if [ "${DISABLEUPDATECHECK__DEFAULT:-true}" = true ]; then
  expected="NO_UPDATE_CHECK=set:1"
fi
if [ "${DISABLETELEMETRY__DEFAULT:-false}" = true ]; then
  expected="$expected TELEMETRY=set:0"
else
  expected="$expected TELEMETRY=unset"
fi
check "openspec sees the second install's environment ($expected)" \
  [ "$(seen_env -u OPENSPEC_NO_UPDATE_CHECK -u OPENSPEC_TELEMETRY)" = "$expected" ]

# Exactly one installation remains reachable.
check "one openspec is on PATH, the wrapper" [ "$(type -ap openspec | sort -u)" = "$WRAPPER" ]
check "one prefix and one wrapper remain, nothing staged or set aside" single_installation
check "the prefix holds the second install's version" [ "$(installed_version)" = "$second" ]

reportResults
