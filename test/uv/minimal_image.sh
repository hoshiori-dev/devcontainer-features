#!/bin/sh
# Scenario "minimal_image": debian:12 without curl or CA certificates, built from
# minimal_image/Dockerfile ("Minimal image").
set -e

# The test library is a bash script. Re-execute with bash, adding it from the image's apk
# repositories on Alpine (inside this test container only).
if [ -z "${FEATURE_TEST_BASH:-}" ]; then
    command -v bash >/dev/null 2>&1 || apk add --no-cache bash >/dev/null
    FEATURE_TEST_BASH=1 exec bash "$0" "$@"
fi

# shellcheck source=/dev/null
. dev-container-features-test-lib

apt_sources_and_keys() {
    find /etc/apt /usr/share/keyrings -type f \
        \( -path '/etc/apt/sources.list*' -o -path '/etc/apt/trusted.gpg*' -o -path '/usr/share/keyrings/*' \) \
        -exec sha256sum {} + | sort
}

check "curl was installed" command -v curl
check "CA certificates were installed" test -s /etc/ssl/certs/ca-certificates.crt
check "uv runs" uv --version
check "apt sources and signing keys are unchanged" \
    [ "$(apt_sources_and_keys)" = "$(cat /opt/uv-test/apt-before.sha256)" ]

reportResults
