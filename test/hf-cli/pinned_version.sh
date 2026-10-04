#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the minimum accepted release is installed" "$HOME/.hf-cli/venv/bin/python" -c 'import importlib.metadata; assert importlib.metadata.version("huggingface_hub") == "1.27.0"'
check "the pinned CLI runs" hf version
check "the pinned environment is installer-managed" test -f "$HOME/.hf-cli/venv/.hf_installer_marker"
reportResults
