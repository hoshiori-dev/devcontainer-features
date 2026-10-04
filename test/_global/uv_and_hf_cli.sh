#!/usr/bin/env bash
# uv's build-time executable and runtime volume contract must survive hf-cli.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the CLI packages were installed by uv" "$HOME/.hf-cli/venv/bin/python" -c 'import importlib.metadata; assert importlib.metadata.distribution("huggingface_hub").read_text("INSTALLER").strip() == "uv"'
check "the later feature found uv" /usr/local/bin/uv --version
check "the runtime Python directory stays on the volume" [ "$UV_PYTHON_INSTALL_DIR" = /var/lib/uv/python ]
check "the uv volume is mounted" bash -c 'grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* /var/lib/uv " /proc/self/mountinfo'
check "no build-time files were copied into the volume" [ -z "$(ls -A /var/lib/uv)" ]
check "uv group grants write access after UID remapping" [ "$(stat -c '%G %a' /var/lib/uv)" = 'uv 2775' ]
check "the remote user can write the volume" test -w /var/lib/uv
check "the CLI works with the empty mounted volume" hf version
reportResults
