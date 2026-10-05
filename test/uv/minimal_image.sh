#!/usr/bin/env bash
# Scenario "minimal_image": debian:12 without curl or CA certificates, built from minimal_image/Dockerfile ("Minimal
# image").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Prints the checksum of every apt source and signing key, as minimal_image/Dockerfile records them before the install.
apt_sources_and_keys() {
  find /etc/apt /usr/share/keyrings -type f \
    \( -path '/etc/apt/sources.list*' -o -path '/etc/apt/trusted.gpg*' -o -path '/usr/share/keyrings/*' \) \
    -exec sha256sum {} + \
    | sort
}

check "curl was installed" command -v curl
check "CA certificates were installed" test -s /etc/ssl/certs/ca-certificates.crt
check "uv runs" uv --version
check "the package repository configuration and signing keys are unchanged" \
  [ "$(apt_sources_and_keys)" = "$(cat /opt/uv-test/apt-before.sha256)" ]

reportResults
