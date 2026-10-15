#!/usr/bin/env bash
# Scenario "fail_epel_unavailable": the CLI installed the feature on almalinux:9, which enabled EPEL. The script undoes
# that, disables the distribution's extras repository, which carries epel-release, and runs the installer again: it
# must fail naming EPEL and install nothing ("EPEL unavailable").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# The state the re-run meets: no apptainer, no EPEL, and no repository that offers epel-release.
as_root dnf -y remove apptainer epel-release >/dev/null
as_root rm -f /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-testing.repo /etc/yum.repos.d/epel-cisco-openh264.repo
as_root sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/almalinux-extras.repo
# Preconditions, not checks: without them the checks below would pass without showing what their labels state.
if as_root dnf repolist --enabled | awk '$1 == "epel" || $1 == "extras" { found = 1 } END { exit !found }'; then
  echo "the re-run must meet an image without epel and extras enabled" >&2
  exit 1
fi

status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"

check "the installer exits non-zero" test "${status}" -ne 0
check "the failure names epel-release and EPEL" \
  bash -c "grep -q 'cannot install epel-release' <<<\"\$1\" && grep -q 'enable EPEL' <<<\"\$1\"" _ "${output}"
check "apptainer is not installed" bash -c '! rpm -q apptainer'
check "no EPEL repository was configured" bash -c '! ls /etc/yum.repos.d/epel.repo'
check "no temporary install directory remains" no_temporary_dir

reportResults
