#!/bin/sh
# Scenario "tools": two tools, with surrounding whitespace and an empty entry, on the Ubuntu base
# image as vscode ("Tools on PATH", "Tools survive a replaced volume", "Remote user manages
# tools", "Default sources").
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

# The interpreter of a build-time tool's environment lives in the image, not on the volume.
interpreter_in_image() {
    interpreter=$(readlink -f "/usr/local/share/uv/tools/$1/bin/python")
    echo "$1 runs on $interpreter"
    case "$interpreter" in
        /usr/local/share/uv/python/*) [ -x "$interpreter" ] ;;
        *) return 1 ;;
    esac
}

# Tools survive a replaced volume: this container starts with a new, empty volume.
check "the volume is mounted at $VOLUME" is_mount "$VOLUME"
check "the volume is new and empty" is_empty_dir "$VOLUME"

# Assert the image layout before Python writes __pycache__ with the user's umask.
# shellcheck disable=SC2016
check "every entry belongs to uv" sh -c 'test -z "$(find /usr/local/share/uv ! -group uv -print -quit)"'
# shellcheck disable=SC2016
check "every non-link has group write" sh -c 'test -z "$(find /usr/local/share/uv ! -type l ! -perm -0020 -print -quit)"'
# shellcheck disable=SC2016
check "no non-link has other-write" sh -c 'test -z "$(find /usr/local/share/uv ! -type l -perm -0002 -print -quit)"'
# shellcheck disable=SC2016
check "every directory has setgid" sh -c 'test -z "$(find /usr/local/share/uv -type d ! -perm -2000 -print -quit)"'

# Tools on PATH.
check "pycowsay is found by name" [ "$(command -v pycowsay)" = /usr/local/share/uv/bin/pycowsay ]
check "cowsay is found by name" [ "$(command -v cowsay)" = /usr/local/share/uv/bin/cowsay ]
check "pycowsay runs" sh -c 'pycowsay hello >/dev/null'
check "cowsay runs" sh -c 'cowsay -t hello >/dev/null'
check "pycowsay's interpreter is in the image" interpreter_in_image pycowsay
check "cowsay's interpreter is in the image" interpreter_in_image cowsay
check "the volume is still empty after running the tools" is_empty_dir "$VOLUME"

# Default sources: the feature sets no uv variable beyond its five locations and no configuration file.
check "the only uv variables are the feature's five" [ "$(env | grep '^UV_' | cut -d= -f1 | sort | tr '\n' ' ')" \
    = "UV_CACHE_DIR UV_LINK_MODE UV_PYTHON_INSTALL_DIR UV_TOOL_BIN_DIR UV_TOOL_DIR " ]
check "no system uv.toml" [ ! -e /etc/uv/uv.toml ]
check "no user uv.toml" [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" ]

# Remote user manages tools, without elevated privileges.
check "the remote user is not root" [ "$(id -u)" != 0 ]
check "the remote user upgrades a build-time tool" uv tool upgrade pycowsay
check "the remote user reinstalls a build-time tool" uv tool install --reinstall pycowsay
check "the remote user removes a build-time tool" uv tool uninstall cowsay
check "the remote user installs a new tool" uv tool install pyjokes
check "the new tool runs by name" sh -c 'pyjoke >/dev/null'

reportResults
