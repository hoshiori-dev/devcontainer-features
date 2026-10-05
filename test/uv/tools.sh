#!/usr/bin/env bash
# Scenario "tools": two tools, with surrounding whitespace and an empty entry, on the Ubuntu base image as vscode
# ("Tools on PATH", "Tools survive a replaced volume", "Remote user manages tools", "Default sources", "Nothing
# writable by every user").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly VOLUME_DIR="/var/lib/uv"
readonly SHARE_DIR="/usr/local/share/uv"

is_mount() {
  grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* $1 " /proc/self/mountinfo
}

is_empty_dir() {
  [[ -d "$1" && -z "$(ls -A "$1")" ]]
}

# Whether find, given the arguments after the tool tree, matches nothing in it.
tool_tree_has_none() {
  local found
  found="$(find "${SHARE_DIR}" "$@" -print -quit)"
  [[ -z "${found}" ]]
}

# Whether the interpreter of the build-time tool $1 lives in the image, not on the volume.
interpreter_in_image() {
  local interpreter
  interpreter="$(readlink -f "${SHARE_DIR}/tools/$1/bin/python")"
  printf '%s\n' "$1 runs on ${interpreter}"
  [[ "${interpreter}" == "${SHARE_DIR}"/python/* && -x "${interpreter}" ]]
}

# Prints the names of the uv variables in the environment, sorted, each followed by a space.
uv_variable_names() {
  env | grep '^UV_' | cut -d= -f1 | sort | tr '\n' ' '
}

# Tools survive a replaced volume: this container starts with a new, empty volume.
check "${VOLUME_DIR} is a mount of the volume" is_mount "${VOLUME_DIR}"
check "the volume is new and empty" is_empty_dir "${VOLUME_DIR}"

# Remote user in the group, Nothing writable by every user: asserted before Python writes __pycache__ with the user's
# umask.
check "everything under ${SHARE_DIR} belongs to the group uv" tool_tree_has_none ! -group uv
check "everything but links under ${SHARE_DIR} is writable by the group" tool_tree_has_none ! -type l ! -perm -0020
check "nothing under ${SHARE_DIR} is writable by every user" tool_tree_has_none ! -type l -perm -0002
check "every directory under ${SHARE_DIR} has setgid" tool_tree_has_none -type d ! -perm -2000

# Tools on PATH.
check "pycowsay is found by name" [ "$(command -v pycowsay)" = "${SHARE_DIR}/bin/pycowsay" ]
check "cowsay is found by name" [ "$(command -v cowsay)" = "${SHARE_DIR}/bin/cowsay" ]
check "pycowsay runs by name" pycowsay hello
check "cowsay runs by name" cowsay -t hello
check "pycowsay's interpreter resolves outside the volume" interpreter_in_image pycowsay
check "cowsay's interpreter resolves outside the volume" interpreter_in_image cowsay
check "the volume is still empty after the tools ran" is_empty_dir "${VOLUME_DIR}"

# Default sources: the feature sets no uv variable beyond its five locations and no configuration file.
check "the only uv variables are the feature's five" \
  [ "$(uv_variable_names)" = "UV_CACHE_DIR UV_LINK_MODE UV_PYTHON_INSTALL_DIR UV_TOOL_BIN_DIR UV_TOOL_DIR " ]
check "the image has no system uv.toml" [ ! -e /etc/uv/uv.toml ]
check "the remote user has no uv.toml" [ ! -e "${XDG_CONFIG_HOME:-${HOME}/.config}/uv/uv.toml" ]

# Remote user manages tools, without elevated privileges.
check "the remote user is not root" [ "$(id -u)" != 0 ]
check "the remote user upgrades a build-time tool" uv tool upgrade pycowsay
check "the remote user reinstalls a build-time tool" uv tool install --reinstall pycowsay
check "the remote user removes a build-time tool" uv tool uninstall cowsay
check "the remote user adds a tool" uv tool install pyjokes
check "the added tool runs by name" pyjoke

reportResults
