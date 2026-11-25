#!/usr/bin/env bash
# The exact release 1.1.0, the oldest the feature accepts, installs and works like the default installation.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

before="$(tree_manifest)"

check "freecadcmd reports release 1.1.0" reports_release 1.1.0
check "the marker records release 1.1.0" marker_records 1.1.0
check "freecad and freecadcmd link to the launchers" links_target_launchers
check "a script models a solid and exports STEP and STL" models_and_exports
check "the notes' command-line example writes its output, and exits non-zero when it raises" \
  notes_example_follows_script
check "running FreeCAD as root leaves the installation tree unchanged" test "$(tree_manifest)" = "${before}"
check "an X server starts for the GUI checks" start_x_server
check "the notes' GUI example renders a 3D view through the X server" gui_renders_view

reportResults
