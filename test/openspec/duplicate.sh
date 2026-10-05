#!/usr/bin/env bash
# Install-twice test ("Different options the second time"): openspec is installed first with version 1.13.1,
# disableUpdateCheck false, and disableTelemetry true, then with the defaults: version latest, disableUpdateCheck
# true, and disableTelemetry false. The first install's values arrive as VERSION, DISABLEUPDATECHECK, and
# DISABLETELEMETRY, the second's as VERSION__DEFAULT, DISABLEUPDATECHECK__DEFAULT, and DISABLETELEMETRY__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# lib.sh is next to this script in the workspace folder, which shellcheck does not see from where it runs.
# shellcheck source=/dev/null
source ./lib.sh

# "Different options the second time" runs only with these two installs: the second replaces another version and
# changes both variables, and every expected value below is written for them.
if [[ "${VERSION-}" != 1.13.1 || "${DISABLEUPDATECHECK-}" != false || "${DISABLETELEMETRY-}" != true \
  || "${VERSION__DEFAULT-}" != latest || "${DISABLEUPDATECHECK__DEFAULT-}" != true \
  || "${DISABLETELEMETRY__DEFAULT-}" != false ]]; then
  printf '%s\n' \
    '"Different options the second time" would not run: it needs version, disableUpdateCheck, and disableTelemetry' \
    'as "1.13.1", "false", and "true", then as "latest", "true", and "false", but got' \
    "\"${VERSION-}\", \"${DISABLEUPDATECHECK-}\", and \"${DISABLETELEMETRY-}\", then \"${VERSION__DEFAULT-}\"," \
    "\"${DISABLEUPDATECHECK__DEFAULT-}\", and \"${DISABLETELEMETRY__DEFAULT-}\"" >&2
  exit 1
fi

# The version the second install resolved is the one the registry names as latest; it is read when the test runs,
# and a release between build and test fails once.
latest="$(
  node -e '
    fetch(process.argv[1], { redirect: "error" })
      .then((response) => response.json())
      .then((document) => console.log(document["dist-tags"].latest));
  ' "${REGISTRY}@fission-ai%2fopenspec"
)"
printf '%s\n' "Expecting OpenSpec ${latest}, as $(id -un)"

# Different options the second time.
check "openspec --version prints the version the second install resolved" openspec_reports_version "${latest}"
check "the openspec process sees the environment the second install's options define: OPENSPEC_NO_UPDATE_CHECK=1" \
  openspec_sees OPENSPEC_NO_UPDATE_CHECK set:1 -u OPENSPEC_NO_UPDATE_CHECK
check "the openspec process sees the environment the second install's options define: OPENSPEC_TELEMETRY unset" \
  openspec_sees OPENSPEC_TELEMETRY unset -u OPENSPEC_TELEMETRY

# Requirement "Install the requested version".
check "the package installed as @fission-ai/openspec is at exactly the selected version" \
  openspec_package_is_at "${latest}"

# Requirement "Install twice". The second check reads it as one installation with nothing staged or set aside next
# to it; the spec has no sentence of its own on what an install leaves behind.
check "exactly one OpenSpec installation remains reachable as openspec: one openspec is on PATH" \
  test "$(type -ap openspec | sort -u)" = "${WRAPPER}"
check "exactly one OpenSpec installation remains reachable as openspec: nothing is staged or set aside next to it" \
  single_installation

reportResults
