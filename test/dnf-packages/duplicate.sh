#!/usr/bin/env bash
# Install-twice test: the feature is installed with the `packages` list "bc,file" from its proposals, then with the
# defaults, whose list is empty.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "Installing the feature twice: bc, listed by the first installation, is left installed" rpm -q bc
check "Installing the feature twice: file, listed by the first installation, is left installed" rpm -q file

reportResults
