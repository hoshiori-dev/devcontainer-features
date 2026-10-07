#!/usr/bin/env bash
# uv's build-time executable and runtime volume contract must survive hf-cli.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
# Succeeds when the INSTALLER record of the venv's huggingface_hub distribution names the tool $1.
packages_were_installed_by() {
  "${venv}/bin/python" - "$1" <<'PY'
import importlib.metadata, sys
assert importlib.metadata.distribution("huggingface_hub").read_text("INSTALLER").strip() == sys.argv[1]
PY
}
check "the CLI packages were installed by uv" packages_were_installed_by uv
check "the uv feature's uv runs at /usr/local/bin/uv" /usr/local/bin/uv --version
check "the runtime Python directory stays on the volume" test "${UV_PYTHON_INSTALL_DIR-}" = /var/lib/uv/python
check "the uv volume is mounted" bash -c 'grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* /var/lib/uv " /proc/self/mountinfo'
check "no build-time files were copied into the volume" test -z "$(ls -A /var/lib/uv)"
check "the volume belongs to the group uv, writable by its members" test "$(stat -c '%G %a' /var/lib/uv)" = 'uv 2775'
check "the remote user can write the volume" test -w /var/lib/uv
check "the CLI works with the empty mounted volume" hf version
reportResults
