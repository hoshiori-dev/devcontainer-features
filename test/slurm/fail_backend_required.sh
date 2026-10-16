#!/usr/bin/env bash
# Scenario "fail_backend_required": the CLI installed the feature with the default. The script re-runs the installer
# with apptainer on, in an image without Apptainer, and with an invalid value: each run must fail naming what is
# missing or the accepted values ("Backend required", "Invalid apptainer").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

run_installer() {
  as_root env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root "$@" \
    bash "$(dirname "$0")/_feature/install.sh" 2>&1
}

status=0
output="$(run_installer APPTAINER=on)" || status=$?
printf '%s\n' "${output}"
check "Backend required: apptainer on without Apptainer fails" test "${status}" -ne 0
check "the failure names what is missing" grep -q 'apptainer is on, but the backend needs: Apptainer on PATH' <<<"${output}"
check "no backend template was written" bash -c "! test -e ${SLURM_OCI_TEMPLATE}"

status=0
output="$(run_installer APPTAINER=maybe)" || status=$?
printf '%s\n' "${output}"
check "Invalid apptainer: a value outside auto, on, off fails" test "${status}" -ne 0
check "the failure names the accepted values" grep -q 'use auto, on, or off' <<<"${output}"

# Both runs fail before any package, seed, or key change, so nothing needs restoring.
check "the cluster still runs" node_idle

reportResults
