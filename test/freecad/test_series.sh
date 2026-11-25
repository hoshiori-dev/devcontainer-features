#!/usr/bin/env bash
# The series 1.1 selects its newest stable release, which models and exports like the default installation.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

before="$(tree_manifest)"
# The newest 1.1 release when the test runs, read from the release listing; a release between build and test fails
# once.
newest="$(newest_release 1.1)"

check "freecadcmd reports the newest stable 1.1 release" reports_release "${newest}"
check "the marker records that release" marker_records "${newest}"
check "a script models a solid and exports STEP and STL" models_and_exports
check "a script's sys.exit status reaches the caller" exit_status_reaches_caller
check "freecad runs a script on the offscreen platform" gui_runs_offscreen
check "running FreeCAD as root leaves the installation tree unchanged" test "$(tree_manifest)" = "${before}"

reportResults
