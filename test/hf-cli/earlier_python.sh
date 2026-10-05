#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# Succeeds when the interpreter $1 is Python 3.9.
is_python_3_9() {
  "$1" -c 'import sys; assert sys.version_info[:2] == (3, 9)'
}
check "the earlier candidate is genuinely Python 3.9" is_python_3_9 /usr/local/python/current/bin/python3
# Succeeds when the CLI's venv was created from the Python 3.12 under /usr/local, the later candidate.
later_candidate_backs_the_venv() {
  "${HOME}/.hf-cli/venv/bin/python" - <<'PY'
import sys
assert sys.version_info[:2] == (3, 12)
assert sys.base_prefix == "/usr/local"
PY
}
check "the CLI's virtual environment uses the later usable candidate" later_candidate_backs_the_venv
check "the old interpreter remains unchanged" is_python_3_9 /usr/bin/python3
check "hf runs with the later candidate" hf version
reportResults
