#!/usr/bin/env bash
set -euo pipefail

# TODO(#43): compatibility.json omits Tumbleweed arm64 after native package digest failures there. Restore that
# combination once upstream fixes the cause.

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "installed without packages, the feature installs no bc" bash -c '! rpm -q bc'
check "installed without packages, the feature installs no file" bash -c '! rpm -q file'

reportResults
