#!/bin/sh
# Scenario "pinned_release": version 0.12.16 on alpine:3.24 ("Pinned release", "musl image"). POSIX sh, because
# alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The scenario's image is a musl image; the architecture is the runner's, so a local arm64 run passes too.
machine="$(uname -m)"

check "uv --version reports exactly the pinned release and the musl target" \
  [ "$(uv --version)" = "uv 0.12.16 (${machine}-unknown-linux-musl)" ]
check "uvx --version reports exactly the pinned release and the musl target" \
  [ "$(uvx --version)" = "uvx 0.12.16 (${machine}-unknown-linux-musl)" ]

reportResults
