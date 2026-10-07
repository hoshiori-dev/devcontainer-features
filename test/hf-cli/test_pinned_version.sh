#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
installed="$("${venv}/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')"
check "the minimum accepted release is installed" test "${installed}" = 1.27.0
check "the pinned CLI runs" hf version
check "the pinned environment is installer-managed" test -f "${venv}/.hf_installer_marker"
reportResults
