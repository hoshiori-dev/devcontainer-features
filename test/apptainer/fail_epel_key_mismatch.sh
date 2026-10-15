#!/usr/bin/env bash
# Scenario "fail_epel_key_mismatch": the CLI installed the feature on almalinux:9. The script removes apptainer and
# EPEL's repository files but keeps epel-release installed, so the installer's `dnf install epel-release` changes
# nothing, and replaces the key file with another key: the installer must fail naming the fingerprint it found and
# install no EPEL package ("Key mismatch"). A second run with a VERSION_ID the feature has no pin for must fail naming
# the release ("Unpinned release").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly EPEL_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9"
readonly OTHER_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9"

as_root dnf -y remove apptainer >/dev/null
# epel-release at the newest version extras offers, so the installer's `dnf install epel-release` changes nothing and
# the swapped key stays in place.
as_root dnf -y upgrade epel-release >/dev/null
as_root rm -f /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel-testing.repo /etc/yum.repos.d/epel-cisco-openh264.repo
as_root cp "${OTHER_KEY}" "${EPEL_KEY}"
# Preconditions, not checks.
if ! rpm -q epel-release >/dev/null; then
  echo "the re-run must meet an image with epel-release still installed" >&2
  exit 1
fi

# Key mismatch
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
check "with another key in EPEL's key file the installer exits non-zero" test "${status}" -ne 0
check "the failure names the EPEL key file and the fingerprint found" \
  bash -c "grep -q 'RPM-GPG-KEY-EPEL-9 is not the EPEL 9 signing key' <<<\"\$1\"" _ "${output}"
check "apptainer is not installed" bash -c '! rpm -q apptainer'

# Unpinned release: a VERSION_ID the feature has no fingerprint for, with EPEL still unconfigured.
as_root cp /etc/os-release /tmp/os-release.backup
as_root sed -i 's/^VERSION_ID=.*/VERSION_ID="10.0"/' /etc/os-release
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root cp /tmp/os-release.backup /etc/os-release
check "with an unpinned EPEL release the installer exits non-zero" test "${status}" -ne 0
check "the failure names the release" \
  bash -c "grep -q 'no pinned EPEL signing key for release 10' <<<\"\$1\"" _ "${output}"
check "apptainer is still not installed" bash -c '! rpm -q apptainer'
check "no EPEL repository was configured" bash -c '! ls /etc/yum.repos.d/epel.repo'

reportResults
