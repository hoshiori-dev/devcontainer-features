#!/usr/bin/env bash
# Scenario: godot installed with version "4.6" on fedora:44, which selects the release tagged 4.6-stable.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/headless.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check "godot --version reports 4.6.stable.official. followed by a commit hash" godot_reports_version 4.6

make_project "${work}/project"
check "godot --headless --path <project> --quit on a minimal project exits 0" \
  godot --headless --path "${work}/project" --quit

reportResults
