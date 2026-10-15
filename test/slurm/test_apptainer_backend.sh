#!/usr/bin/env bash
# Scenario "test_apptainer_backend": the apptainer feature is installed first and the option is left at auto on an
# image whose Slurm is 23.02 or newer; the backend is configured, and a job step runs inside an Apptainer sandbox.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

work="$(mktemp -d)"

build_sandbox() {
  apptainer build --sandbox "${work}/alpine" docker://docker.io/library/alpine:3.22 >/dev/null 2>&1
}

step_in_sandbox() {
  local out
  # Slurm resolves a bare command through the host's PATH before entering the container; an absolute path that exists
  # in the image is passed as it is.
  out="$(srun --container "${work}/alpine" /bin/cat /etc/os-release 2>&1)" || { printf '%s\n' "${out}" >&2; return 1; }
  grep -qx 'ID=alpine' <<<"${out}"
}

batch_in_sandbox() {
  local out
  (cd "${work}" && sbatch --wait --output=job.out --container "${work}/alpine" --wrap '/bin/cat /etc/os-release') >/dev/null || return
  out="$(<"${work}/job.out")"
  grep -qx 'ID=alpine' <<<"${out}"
}

check "Backend decided: the template and oci.conf exist and are equal" backend_files_present
check "the local cluster is ready" node_idle
check "a sandbox is built from a small OCI image" build_sandbox
check "Job step in a sandbox: srun --container runs the step inside the sandbox" step_in_sandbox
check "Batch job in a sandbox: sbatch --container runs the job inside the sandbox" batch_in_sandbox
as_root bash -c "printf '# user-owned\n' >> ${SLURM_OCI_CONF}"
check "Existing oci.conf kept: a start leaves an edited oci.conf byte-identical" \
  bash -c "s=\$(sha256sum ${SLURM_OCI_CONF}); ${SLURM_HOOK} >/dev/null && test \"\$(sha256sum ${SLURM_OCI_CONF})\" = \"\$s\""

rm -rf "${work}"
reportResults
