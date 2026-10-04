#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the build's custom HF_HOME was ignored" test ! -e /invalid-hf-home
check "the venv is in the remote home" test -f "$HOME/.hf-cli/venv/.hf_installer_marker"
check "the requested version is installed through the fixed sources" "$HOME/.hf-cli/venv/bin/python" -c 'import importlib.metadata; assert importlib.metadata.version("huggingface_hub") == "1.33.0"'
check "hf runs with build-only variables cleared" env -u HF_HOME -u HF_CLI_PIP_ARGS -u HF_PIP_ARGS hf version
check "pip installs packages when uv is absent" "$HOME/.hf-cli/venv/bin/python" -c 'import importlib.metadata; assert importlib.metadata.distribution("huggingface_hub").read_text("INSTALLER").strip() == "pip"'
reportResults
