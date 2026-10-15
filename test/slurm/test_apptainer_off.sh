#!/usr/bin/env bash
# Scenario "test_apptainer_off": Apptainer is present but the option is off: no template, no oci.conf, and
# srun --container reports that no container runtime is configured.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# Without an oci.conf Slurm ignores --container and runs the step on the node itself: the output is this
# container's hostname, not a sandbox's. (Slurm reports nothing; the spec's wording "reports that no container runtime
# is configured" is met only by this silence, recorded in the PR.)
container_ignored() {
  local out
  out="$(srun --container /tmp hostname 2>&1)" || { printf '%s\n' "${out}" >&2; return 1; }
  [[ "${out}" == "$(uname -n)" ]]
}

check "Backend disabled: no template and no oci.conf exist" no_backend_files
check "Apptainer is installed" apptainer --version
check "the local cluster is ready" node_idle
check "Backend disabled: srun --container runs on the node itself, no runtime being configured" container_ignored

reportResults
