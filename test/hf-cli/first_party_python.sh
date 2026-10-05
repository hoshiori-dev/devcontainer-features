#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
# The first-party feature decides which Python it installs and where, so the expected prefix is read from its
# interpreter.
expected="$(/usr/local/python/current/bin/python3 -c 'import sys; print(sys.base_prefix)')"
actual="$("${venv}/bin/python" -c 'import sys; print(sys.base_prefix)')"
check "the first-party interpreter backs the CLI" test "${actual}" = "${expected}"
check "first-party Python still runs" /usr/local/python/current/bin/python3 --version
# Succeeds when the CLI's interpreter runs in a virtual environment of its own, not in the first-party Python's prefix.
venv_is_isolated() {
  "${venv}/bin/python" -c 'import sys; assert sys.prefix != sys.base_prefix'
}
check "the CLI is isolated from first-party Python" venv_is_isolated
check "development tools were not enabled" bash -c '! command -v flake8'
check "the CLI runs" hf version
reportResults
