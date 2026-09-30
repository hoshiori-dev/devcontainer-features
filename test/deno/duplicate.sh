#!/usr/bin/env bash
# Install-twice test: deno is installed with the first non-default proposal (VERSION, 2.8.0) and
# then with the default (VERSION__DEFAULT, latest), so the second install replaces the first.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

latest="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location \
    https://dl.deno.land/release-latest.txt | tr -d '[:space:]')"
latest="${latest#v}"
if [ "$(id -u)" = 0 ]; then owner=root; else owner="$(id -un)"; fi

check "the two installs used different versions" test "${VERSION}" != "${VERSION__DEFAULT}"
check "deno reports the version latest resolved to (${latest})" bash -c \
    "deno --version | head -n 1 | grep -qx 'deno ${latest} (.*'"
check "deno resolves to /usr/local/bin/deno" test "$(command -v deno)" = /usr/local/bin/deno
no_staging_file() { [ -z "$(find /usr/local/bin -name '.deno.*')" ]; }
check "no staging file is left in /usr/local/bin" no_staging_file
check "the tools tree exists and is owned by ${owner}" bash -c \
    "[ -d /usr/local/share/deno/bin ] && [ -z \"\$(find /usr/local/share/deno ! -user ${owner})\" ]"

reportResults
