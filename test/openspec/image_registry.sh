# shellcheck shell=bash
# Body of the build scenarios "image_registry_ubuntu" and "image_registry_debian" ("Registry
# configured in the image"): the Dockerfile wrote an unreachable registry for the @fission-ai scope
# into root's ~/.npmrc before the feature installed. Runs as root, whose configuration it is.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source ./lib.sh

check "root's npm configuration names another registry for the @fission-ai scope" \
  [ "$(npm config get @fission-ai:registry)" = "https://example.invalid/" ]
check "every package came from the public npm registry" all_from_registry
latest=$(registry_latest)
check "openspec --version prints the registry's latest version ($latest)" [ "$(openspec --version)" = "$latest" ]

reportResults
