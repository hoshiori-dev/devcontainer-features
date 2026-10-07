#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Succeeds when the CLI's venv was created from the Python under /usr/local, the interpreter the image already has.
existing_interpreter_backs_the_venv() {
  "${HOME}/.hf-cli/venv/bin/python" -c 'import sys; assert sys.base_prefix == "/usr/local"'
}
check "the CLI's virtual environment uses the existing interpreter" existing_interpreter_backs_the_venv
check "no distribution Python was added" bash -c '! dpkg-query -W python3 >/dev/null 2>&1'
check "hf runs" hf version
reportResults
