#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
check "the build's custom HF_HOME was ignored" test ! -e /invalid-hf-home
check "the venv is in the remote home" test -f "${venv}/.hf_installer_marker"
installed="$("${venv}/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')"
check "the requested version is installed through the fixed sources" test "${installed}" = 1.33.0
check "hf runs with build-only variables cleared" env -u HF_HOME -u HF_CLI_PIP_ARGS -u HF_PIP_ARGS hf version
# Succeeds when the INSTALLER record of the venv's huggingface_hub distribution names the tool $1.
packages_were_installed_by() {
  "${venv}/bin/python" - "$1" <<'PY'
import importlib.metadata, sys
assert importlib.metadata.distribution("huggingface_hub").read_text("INSTALLER").strip() == sys.argv[1]
PY
}
check "the optional uv installs packages" packages_were_installed_by uv
reportResults
