#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "bc is installed as if the whitespace and the empty entry were absent" rpm -q bc
check "file is installed as if the whitespace and the empty entry were absent" rpm -q file

reportResults
