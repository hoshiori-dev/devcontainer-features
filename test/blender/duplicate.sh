#!/usr/bin/env bash
# Install-twice test: blender is installed once with the series 4.5 and then with the defaults, so the second
# installation replaces the first. Option values arrive as VERSION and VERSION__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

latest="$(newest_release)"

check "the first installation selected the series 4.5" test "${VERSION}" = 4.5
check "the second installation selected the default" test "${VERSION__DEFAULT}" = latest
check "blender reports the release of the last installation" reports_release "${latest}"
check "the marker records the last installation" test "$(cat "${TREE}/.devcontainer-feature-blender")" = "${latest}"
check "/usr/local/bin/blender links to the executable" link_targets_executable
check "no staging directory is left in /opt" bash -c '! compgen -G "/opt/.blender-feature.*"'
check "the installation belongs to root and only root can write it" tree_is_root_only
check "Cycles renders a frame after the replacement" renders_frame CYCLES

reportResults
