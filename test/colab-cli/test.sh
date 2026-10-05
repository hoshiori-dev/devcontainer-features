#!/usr/bin/env bash
# Default installation on every compatibility image, including an empty uv runtime volume.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# Computed test paths cannot be resolved by shellcheck.
# shellcheck source=/dev/null
source "$(dirname "$0")/assertions.sh"

check "uv dependency is installed automatically" uv --version
check "colab reports the latest stable release" reports_release "$(latest_release)"
check "colab help needs no credentials" colab --help
check "colab uses in-image managed Python 3.12" image_interpreter
check "colab version works in a login shell" bash -lc 'colab version'
check "colab help works in a login shell" bash -lc 'colab --help'
check "uv runtime volume is empty" test -z "$(ls -A /var/lib/uv)"
check "uv runtime volume is mounted" mountpoint /var/lib/uv
check "installed files are not world writable" not_world_writable
check "PATH contains one uv tool entry" one_path_entry
check "uv lists google-colab-cli" bash -c 'uv tool list | grep -q "^google-colab-cli "'
reportResults
