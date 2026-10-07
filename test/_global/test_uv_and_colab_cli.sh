#!/usr/bin/env bash
# Explicit uv options and runtime integration must survive installation of colab-cli.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

uv_has_selected_version() {
  local output
  output="$(/usr/local/bin/uv --version)"
  [[ "${output}" == 'uv 0.12.16' || "${output}" == 'uv 0.12.16 '* ]]
}

# Check uv's five runtime variables in both the ordinary environment and a login shell.
uv_environment_is_preserved() {
  local output
  # The uv variables expand inside the shell being checked.
  # shellcheck disable=SC2016
  output="$(bash "$1" 'printf "%s|%s|%s|%s|%s" \
    "${UV_PYTHON_INSTALL_DIR}" "${UV_CACHE_DIR}" "${UV_TOOL_DIR}" "${UV_TOOL_BIN_DIR}" "${UV_LINK_MODE}"')"
  [[ "${output}" == '/var/lib/uv/python|/var/lib/uv/cache|/usr/local/share/uv/tools|/usr/local/share/uv/bin|copy' ]]
}

colab_uses_selected_release_and_interpreter() {
  /usr/local/share/uv/tools/google-colab-cli/bin/python -I -c '
import sys
from importlib.metadata import version
from pathlib import Path
assert version("google-colab-cli") == "0.7.2"
assert sys.version_info[:2] == (3, 12)
assert Path(sys.executable).resolve().is_relative_to("/usr/local/share/uv/python")'
}

check "explicit uv version survives the dependency installation" uv_has_selected_version
check "uv runtime variables remain configured" uv_environment_is_preserved -c
check "uv runtime variables remain configured in login shells" uv_environment_is_preserved -lc
check "uv uses its configured tool directory" test "$(uv tool dir)" = /usr/local/share/uv/tools
check "uv uses its configured executable directory" test "$(uv tool dir --bin)" = /usr/local/share/uv/bin
check "uv runtime volume is mounted" mountpoint /var/lib/uv
check "uv runtime volume starts empty" test -z "$(ls -A /var/lib/uv)"
check "uv runtime volume remains writable by the remote user" test -w /var/lib/uv
check "first configured uv tool remains runnable" pycowsay hello
check "second configured uv tool remains runnable" cowsay -t hello
check "colab retains its own version and in-image interpreter" colab_uses_selected_release_and_interpreter
check "colab version works with the empty volume" colab version
check "colab help works with the empty volume" colab --help
check "colab works in a login shell" bash -lc 'colab version'
check "the remote user is not root" test "$(id -u)" != 0
check "the remote user can remove a configured uv tool" uv tool uninstall cowsay
check "the other configured tool remains runnable" pycowsay hello
check "colab remains runnable after managing another tool" colab version
reportResults
