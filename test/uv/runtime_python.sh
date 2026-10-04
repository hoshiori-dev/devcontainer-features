#!/bin/sh
# Scenario "runtime_python": defaults on the Ubuntu base image as vscode ("Runtime interpreter on
# the volume", "Workspace install across filesystems").
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
WORK=$(mktemp -d)
LOG="$WORK/uv.log"
# A named volume and a bind-mounted workspace can share the runner's backing filesystem.
# Exercise UV_LINK_MODE across actual filesystems with a temporary cache on Docker's tmpfs.
CROSS_FS_CACHE=$(mktemp -d /dev/shm/uv-cross-filesystems.XXXXXX)

is_empty_dir() {
    [ -d "$1" ] && [ -z "$(ls -A "$1")" ]
}

resolves_to_volume() {
    target=$(readlink -f "$1")
    echo "$1 -> $target"
    case "$target" in
        "$VOLUME"/python/*) [ -x "$target" ] ;;
        *) return 1 ;;
    esac
}

# Creates the environment $1 and installs a package into it (further arguments go to uv pip
# install); uv's output, where a link-mode warning would appear, goes to $LOG.
install_into() {
    env_dir=$1
    shift
    uv venv "$env_dir" || return
    status=0
    UV_CACHE_DIR="$CROSS_FS_CACHE" uv pip install --python "$env_dir/bin/python" "$@" pycowsay >"$LOG" 2>&1 || status=$?
    cat "$LOG"
    return "$status"
}

no_link_warning() {
    cat "$LOG"
    ! grep -Eqi 'hardlink|clone|falling back|link mode' "$LOG"
}

check "the volume is new and empty" is_empty_dir "$VOLUME"

# Runtime interpreter on the volume.
check "the remote user creates an environment with a managed interpreter" \
    uv venv --managed-python "$WORK/venv"
check "the interpreter was installed under $VOLUME/python" [ -n "$(ls -A "$VOLUME/python")" ]
check "the environment's interpreter link resolves on the volume" resolves_to_volume "$WORK/venv/bin/python"

# Workspace install across filesystems: the working directory is the bind-mounted workspace.
check "the workspace and the test cache are different filesystems" [ "$(stat -c %d .)" != "$(stat -c %d "$CROSS_FS_CACHE")" ]
check "a package installs into an environment in the workspace" install_into .venv-uv-first
check "the install printed no link-mode fallback warning" no_link_warning
check "a cached package installs offline into another workspace environment" install_into .venv-uv-second --offline
check "the offline install printed no link-mode fallback warning" no_link_warning
check "the installed package runs" sh -c './.venv-uv-second/bin/pycowsay hello >/dev/null'

rm -rf .venv-uv-first .venv-uv-second "$WORK" "$CROSS_FS_CACHE"

reportResults
