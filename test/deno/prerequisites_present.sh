#!/usr/bin/env bash
# Scenario: base:ubuntu24.04 already has curl, ca-certificates, and unzip, so the feature installs and removes no
# package.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "deno --version runs by name" bash -c "deno --version | head -n 1 | grep -q '^deno '"
check "the set of installed packages is unchanged" bash -c 'dpkg-query -W | diff /opt/packages-before.txt -'

reportResults
