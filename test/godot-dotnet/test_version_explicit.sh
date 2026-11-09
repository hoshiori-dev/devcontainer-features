#!/usr/bin/env bash
# Scenario: godot-dotnet installed with version "4.6.3" on debian:12, which also builds and runs a minimal C# project,
# so a release other than the latest restores its own Godot.NET.Sdk.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/headless.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

check "godot --version reports 4.6.3.stable.mono.official. followed by a commit hash" godot_reports_version 4.6.3

make_project "${work}/project"
check "godot --headless --path <project> --quit on a minimal project exits 0" \
  godot --headless --path "${work}/project" --quit

check "a minimal C# project for 4.6.3 can be written" make_csharp_project "${work}/csharp"
check "godot --headless --path <project> --build-solutions --quit on a minimal C# project exits 0 and builds it" \
  builds_csharp_project "${work}/csharp" "${work}/build.log"
check "godot --headless --path <project> --quit-after <frames> then prints the line of the C# script" \
  runs_csharp_project "${work}/csharp" "${work}/run.log"

reportResults
