#!/usr/bin/env bash
# Scenario: godot installed with version "4.6.3-stable" on mcr.microsoft.com/devcontainers/base:ubuntu24.04, as the
# non-root remote user vscode.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/headless.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check "godot --version reports 4.6.3.stable.official. followed by a commit hash" godot_reports_version 4.6.3

make_project "${work}/project"
check "godot --headless --path <project> --quit on a minimal project exits 0" \
  godot --headless --path "${work}/project" --quit

reportResults
