#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "the listed package less is installed" rpm -q less
check "the recommended package file is not installed with installRecommends=false" bash -c '! rpm -q file'

reportResults
