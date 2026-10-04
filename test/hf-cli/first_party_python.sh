#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
expected=$(/usr/local/python/current/bin/python3 -c 'import sys; print(sys.base_prefix)')
actual=$("$HOME/.hf-cli/venv/bin/python" -c 'import sys; print(sys.base_prefix)')
check "the first-party interpreter backs the CLI" [ "$actual" = "$expected" ]
check "first-party Python still runs" /usr/local/python/current/bin/python3 --version
check "the CLI is isolated from first-party Python" "$HOME/.hf-cli/venv/bin/python" -c 'import sys; assert sys.prefix != sys.base_prefix'
check "development tools were not enabled" bash -c '! command -v flake8'
check "the CLI runs" hf version
reportResults
