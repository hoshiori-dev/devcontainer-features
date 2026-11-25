#!/usr/bin/env bash
# Install-twice test: freecad is installed once with the series 1.1 and then with the defaults, so the second
# installation keeps the first when both select the same release and replaces it otherwise. Option values arrive as
# VERSION and VERSION__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

latest="$(newest_release)"

check "the first installation selected the series 1.1" test "${VERSION}" = 1.1
check "the second installation selected the default" test "${VERSION__DEFAULT}" = latest
check "freecadcmd reports the release of the last installation" reports_release "${latest}"
check "the marker records the last installation" marker_records "${latest}"
check "freecad and freecadcmd link to the launchers" links_target_launchers
check "the feature adds no other command" adds_two_commands
check "no staging directory is left in /opt" bash -c '! compgen -G "/opt/.freecad-feature.*"'
check "the installation belongs to root and only root can write it" tree_is_root_only
check "a script models a solid and exports STEP and STL" models_and_exports

reportResults
