#!/bin/sh
# Install-twice test ("Different options"): uv is installed first with non-default options (the
# second proposal of each option: a pinned version and a tool), then with the defaults. The values
# arrive as VERSION and TOOLSTOINSTALL, and as VERSION__DEFAULT and TOOLSTOINSTALL__DEFAULT.
set -e

# The test library is a bash script. Re-execute with bash, adding it from the image's apk
# repositories on Alpine (inside this test container only).
if [ -z "${FEATURE_TEST_BASH:-}" ]; then
    command -v bash >/dev/null 2>&1 || apk add --no-cache bash >/dev/null
    FEATURE_TEST_BASH=1 exec bash "$0" "$@"
fi

# shellcheck source=/dev/null
. dev-container-features-test-lib

VOLUME=/var/lib/uv

is_mount() {
    grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* $1 " /proc/self/mountinfo
}

is_empty_dir() {
    [ -d "$1" ] && [ -z "$(ls -A "$1")" ]
}

latest_release() {
    location=$(curl --proto '=https' --tlsv1.2 -fsS -o /dev/null -w '%{redirect_url}' \
        https://github.com/astral-sh/uv/releases/latest)
    echo "${location##*/}"
}

# The package name of a toolsToInstall entry, without extra or constraint. The proposals' tools
# install an executable of the same name.
tool_name() {
    name=$1
    for stop in '[' '=' '~' '!' '<' '>' '@'; do
        name=${name%%"$stop"*}
    done
    echo "$name"
}

check "the volume is mounted at $VOLUME" is_mount "$VOLUME"
check "the volume is still empty after two installs" is_empty_dir "$VOLUME"

second=${VERSION__DEFAULT:-latest}
if [ "$second" = latest ]; then
    second=$(latest_release)
fi
echo "First install: version=${VERSION:-} toolsToInstall=${TOOLSTOINSTALL:-}"
echo "Second install: version=${VERSION__DEFAULT:-} toolsToInstall=${TOOLSTOINSTALL__DEFAULT:-} (uv $second)"
check "uv reports the second install's release" [ "$(uv --version | cut -d' ' -f2)" = "$second" ]
check "uvx reports the second install's release" [ "$(uvx --version | cut -d' ' -f2)" = "$second" ]

old_ifs=$IFS
IFS=,
set -f
tools=""
for entry in ${TOOLSTOINSTALL:-} ${TOOLSTOINSTALL__DEFAULT:-}; do
    entry=$(echo "$entry" | tr -d '[:space:]')
    if [ -n "$entry" ]; then
        tools="$tools $(tool_name "$entry")"
    fi
done
set +f
IFS=$old_ifs
for tool in $tools; do
    check "tool $tool runs by name" sh -c "command -v '$tool' && '$tool' hello >/dev/null"
done

reportResults
