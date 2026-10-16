#!/usr/bin/env bash
# Scenario "fail_unsupported_platform": the CLI installed the feature on debian:12. The script runs the installer again
# with /etc/os-release naming an unsupported distribution, and again with Debian on an architecture the release has
# no package for: each run must fail naming what it detected and change nothing ("Unsupported distribution").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

work_dir="$(mktemp -d)"
as_root cp /etc/os-release "${work_dir}/os-release"
before="$(dpkg-query -W -f='${Package} ${Version}\n' | sha256sum)"

# Unsupported distribution
printf '%s\n' 'ID=alpine' 'VERSION_ID=3.22' | as_root tee /etc/os-release >/dev/null
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root cp "${work_dir}/os-release" /etc/os-release
check "on an unsupported distribution the installer exits non-zero" test "${status}" -ne 0
check "the failure names the detected distribution" \
  bash -c "grep -q 'unsupported distribution \"alpine\"' <<<\"\$1\"" _ "${output}"

# Debian on an architecture without a release package: dpkg --print-architecture answered by a stub first on PATH.
mkdir "${work_dir}/bin"
# The $1 and $@ are the stub's own, expanded when it runs, not here.
# shellcheck disable=SC2016
printf '#!/bin/sh\nif [ "$1" = --print-architecture ]; then echo ppc64el; else exec /usr/bin/dpkg "$@"; fi\n' \
  >"${work_dir}/bin/dpkg"
chmod +x "${work_dir}/bin/dpkg"
status=0
output="$(as_root env -i PATH="${work_dir}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root \
  bash "$(dirname "$0")/_feature/install.sh" 2>&1)" || status=$?
printf '%s\n' "${output}"
check "on Debian for another architecture the installer exits non-zero" test "${status}" -ne 0
check "the failure names the architecture and the amd64-only release" \
  bash -c "grep -q 'unsupported architecture \"ppc64el\" on Debian' <<<\"\$1\"" _ "${output}"

after="$(dpkg-query -W -f='${Package} ${Version}\n' | sha256sum)"
check "the installed packages are unchanged by the failed runs" test "${before}" = "${after}"
check "no temporary install directory remains" no_temporary_dir

rm -rf "${work_dir}"
reportResults
