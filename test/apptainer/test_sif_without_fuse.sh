#!/usr/bin/env bash
# Scenario: the test container has no /dev/fuse, as a dev container without the user's runArgs. The remote user runs a
# SIF image with --unsquash; a run without it fails naming /dev/fuse ("SIF without FUSE").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

unsquashed_run_succeeds() {
  local output
  output="$(apptainer exec --unsquash "${APPTAINER_TEST_IMAGE}" cat /etc/os-release)" || return
  grep -qx 'ID=alpine' <<<"${output}"
}

# Whether a run without --unsquash fails and names /dev/fuse.
mounted_run_names_fuse() {
  local output
  if output="$(apptainer exec "${APPTAINER_TEST_IMAGE}" cat /etc/os-release 2>&1)"; then
    printf '%s\n' "the run without --unsquash succeeded; this container should have no /dev/fuse" >&2
    return 1
  fi
  printf '%s\n' "${output}" >&2
  # The Fedora and EPEL builds say "device /dev/fuse not found", the PPA build "fuse: device not found".
  [[ "${output}" == *"/dev/fuse"* || "${output}" == *"fuse: device not found"* ]]
}

# Precondition of the scenario, not a behavior of the feature.
if [[ -e /dev/fuse ]]; then
  echo "the test container has /dev/fuse; this scenario needs a container without it" >&2
  exit 1
fi

check "a SIF image runs with --unsquash" unsquashed_run_succeeds
check "without --unsquash the run fails naming the FUSE device" mounted_run_names_fuse

reportResults
