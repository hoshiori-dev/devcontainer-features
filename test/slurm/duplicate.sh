#!/usr/bin/env bash
# Install-twice test: slurm is installed first with the non-default apptainer value the CLI picks (the enum entry after
# the default: off; on would fail the build without Apptainer, which is why the enum lists off first), then with the
# default (auto). Option values arrive as APPTAINER and APPTAINER__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

check "the first install received apptainer off and the second the default auto" test "${APPTAINER:-}:${APPTAINER__DEFAULT:-}" = off:auto
check "one munged, one slurmctld, and one slurmd run after two installs" one_of_each_daemon
check "the seeded partition lists its one node idle" bash -c 'node_idle && seeded_partition_listed'
check "sbatch --wait runs a job to completion" batch_job_completes
check "the seeded slurm.conf starts with the marker line" marker_is_first_line
check "without Apptainer no backend template exists after the second install" no_backend_files

reportResults
