#!/usr/bin/env bash
# The oldest accepted release, 4.2.0, installs and renders on an Enterprise Linux image.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

before="$(tree_manifest)"

check "blender reports exactly 4.2.0" reports_release 4.2.0
check "Cycles renders a frame in background mode" renders_frame CYCLES
check "Workbench renders a frame in background mode" renders_frame BLENDER_WORKBENCH
check "EEVEE renders a frame under its 4.2 engine id" renders_frame BLENDER_EEVEE_NEXT
check "a script's success or failure sets the exit status" script_status_follows_script
make_extension "${SCRATCH}/probe_ext" probe_ext
check "an extension source validates" validates_extension "${SCRATCH}/probe_ext"
check "running Blender as root leaves the installation tree unchanged" test "$(tree_manifest)" = "${before}"

reportResults
