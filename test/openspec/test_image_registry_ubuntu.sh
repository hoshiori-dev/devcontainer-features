#!/usr/bin/env bash
# Scenario "test_image_registry_ubuntu" ("Registry configured in the image"): a build scenario on
# mcr.microsoft.com/devcontainers/base:ubuntu24.04 whose Dockerfile wrote an unreachable registry for the @fission-ai
# scope into root's ~/.npmrc before the feature installed with default options. Runs as root, whose configuration it
# is.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# lib.sh is next to this script in the workspace folder, which shellcheck does not see from where it runs.
# shellcheck source=/dev/null
source ./lib.sh

# The registry test_image_registry_ubuntu/Dockerfile writes for the @fission-ai scope.
readonly OTHER_REGISTRY="https://example.invalid/"

# The version the registry names as latest when the test runs; a release between build and test fails once.
latest="$(
  node -e '
    fetch(process.argv[1], { redirect: "error" })
      .then((response) => response.json())
      .then((document) => console.log(document["dist-tags"].latest));
  ' "${REGISTRY}@fission-ai%2fopenspec"
)"
printf '%s\n' "Expecting OpenSpec ${latest}, as $(id -un)"

# The scenario's WHEN: the image's user npm configuration names another registry for the @fission-ai scope.
scoped_registry="$(npm config get @fission-ai:registry)"
if [[ "${scoped_registry}" != "${OTHER_REGISTRY}" ]]; then
  printf '%s\n' "\"Registry configured in the image\" would not run: npm reports \"${scoped_registry}\" as the" \
    "registry of the @fission-ai scope, not ${OTHER_REGISTRY}" >&2
  exit 1
fi

# Registry configured in the image.
check "every package the feature installs is downloaded from ${REGISTRY}" all_from_registry

# Omitted version.
check "openspec --version, run as the remote user, prints the version the registry names as latest" \
  openspec_reports_version "${latest}"

reportResults
