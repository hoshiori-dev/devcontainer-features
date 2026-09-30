#!/usr/bin/env bash
# Scenario: base:ubuntu-24.04 already has curl, ca-certificates, and unzip, so the feature
# installs and removes no package.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "deno is installed" bash -c "deno --version | head -n 1 | grep -q '^deno '"
check "the installed packages are unchanged" bash -c 'dpkg-query -W | diff /opt/packages-before.txt -'

reportResults
