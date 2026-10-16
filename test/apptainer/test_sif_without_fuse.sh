#!/usr/bin/env bash
# Scenario: the test container has no /dev/fuse, as a dev container without the user's runArgs. The remote user runs a
# SIF image with --unsquash where the host permits the extraction (reported); a run without it fails naming the FUSE
# device ("SIF without FUSE").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# Whether a run with --unsquash succeeds. Reported, not asserted: extracting the SIF mounts a procfs inside a user
# namespace, which the Docker host may refuse ("can't mount proc filesystem to /proc: operation not permitted" on
# GitHub-hosted runners, where /proc carries Docker's masked paths); it succeeds on hosts that allow it.
unsquashed_run() {
  local output
  if output="$(apptainer exec --unsquash "${APPTAINER_TEST_IMAGE}" cat /etc/os-release 2>&1)" \
    && grep -qx 'ID=alpine' <<<"${output}"; then
    echo "a SIF image ran with --unsquash on this host" >&2
  else
    printf '%s\n' "a SIF image did not run with --unsquash on this host:" "${output}" >&2
  fi
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

unsquashed_run
check "without --unsquash the run fails naming the FUSE device" mounted_run_names_fuse

reportResults
