#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The scenario's list is " bc , file ,, ", so both checks also cover "Spaces and empty entries are ignored" for spaces
# and an empty entry.
check "Listed packages are installed: bc is installed" rpm -q bc
check "Listed packages are installed: file is installed" rpm -q file

reportResults
