#!/bin/sh
# Scenario "pinned_release": version 0.12.16 on alpine:3.24 ("Pinned release", "musl image").
set -e

# The test library is a bash script. Re-execute with bash, adding it from the image's apk
# repositories on Alpine (inside this test container only).
if [ -z "${FEATURE_TEST_BASH:-}" ]; then
    command -v bash >/dev/null 2>&1 || apk add --no-cache bash >/dev/null
    FEATURE_TEST_BASH=1 exec bash "$0" "$@"
fi

# shellcheck source=/dev/null
. dev-container-features-test-lib

expected_target() {
    libc=gnu
    for loader in /lib/ld-musl-*.so.1; do
        if [ -e "$loader" ]; then
            libc=musl
        fi
    done
    echo "$(uname -m)-unknown-linux-$libc"
}

target=$(expected_target)
check "uv reports exactly the pinned release" [ "$(uv --version)" = "uv 0.12.16 ($target)" ]
check "uvx reports exactly the pinned release" [ "$(uvx --version)" = "uvx 0.12.16 ($target)" ]

reportResults
