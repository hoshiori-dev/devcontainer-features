#!/usr/bin/env bash
# The generated duplicate configuration installs 0.7.2 first, then latest.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# Computed test paths cannot be resolved by shellcheck.
# shellcheck source=/dev/null
source "$(dirname "$0")/assertions.sh"
check "later version selection wins" reports_release "$(latest_release)"
check "colab help works after two installs" colab --help
check "interpreter remains in the image" image_interpreter
check "installed files remain not world writable" not_world_writable
check "PATH integration is not duplicated" one_path_entry
if [[ "$(id -u)" != 0 ]]; then
  # $1 and $4 are awk fields, passed literally through the test library's check wrapper.
  # shellcheck disable=SC2016
  check "uv group membership is not duplicated" awk -F: -v user="$(id -un)" '
    $1 == "uv" { groups++; n = split($4, members, ","); for (i = 1; i <= n; i++) if (members[i] == user) listed++ }
    END { exit !(groups == 1 && listed == 1) }
  ' /etc/group
fi
reportResults
