#!/bin/sh
# Scenario: group access after a forced UID change on Alpine.
set -e

# The test library is a bash script. Re-execute with bash, adding it from the image's apk
# repositories on Alpine (inside this test container only).
if [ -z "${FEATURE_TEST_BASH:-}" ]; then
    command -v bash >/dev/null 2>&1 || apk add --no-cache bash >/dev/null
    FEATURE_TEST_BASH=1 exec bash "$0" "$@"
fi

# shellcheck source=/dev/null
. dev-container-features-test-lib

check "the UID changed from the build-time UID" [ "$(id -u)" != 23456 ]
# shellcheck disable=SC2016
check "the user owns neither location" sh -c 'test "$(stat -c %u /var/lib/uv)" != "$(id -u)" && test "$(stat -c %u /usr/local/share/uv)" != "$(id -u)"'
check "the user is in uv" sh -c 'id -Gn | tr " " "\n" | grep -qx uv'
check "the group layout survives the UID change" [ "$(stat -c '%G %a' /var/lib/uv)" = "uv 2775" ]
check "a managed environment can be created" uv venv --managed-python .changed-uid-venv
# shellcheck disable=SC2016
check "its interpreter is on the volume" sh -c 'case "$(readlink -f .changed-uid-venv/bin/python)" in /var/lib/uv/python/*) exit 0;; *) exit 1;; esac'
check "a build-time tool can be reinstalled" uv tool install --reinstall pycowsay
check "a build-time tool can be removed" uv tool uninstall pycowsay
check "a new tool can be installed" uv tool install cowsay
check "the new tool runs" cowsay -t hello
reportResults
