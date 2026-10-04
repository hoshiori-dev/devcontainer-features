#!/usr/bin/env bash
# Default installation on every supported image and architecture.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="$HOME/.hf-cli/venv"
check "no auxiliary build-time harness cache" test ! -e "$HOME/.cache/huggingface/.agent_harnesses.json"
latest=$(python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pypi.org/pypi/huggingface_hub/json') as response:
    print(json.load(response)['info']['version'])
PY
)
installed=$("$venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')
check "default resolves the latest release" [ "$installed" = "$latest" ]
check "hf runs for the remote user" hf version
check "hf is exposed by a root-owned system link" [ "$(stat -c '%U %F' /usr/local/bin/hf)" = 'root symbolic link' ]
check "the link reaches the user's venv" [ "$(readlink -f /usr/local/bin/hf)" = "$venv/bin/hf" ]
check "the environment is installer-managed" "$venv/bin/python" -c 'from huggingface_hub.utils._runtime import installation_method; assert installation_method() == "hf_installer"'
check "the marker exists" test -f "$venv/.hf_installer_marker"
check "the installation belongs to the remote user" [ -z "$(find "$HOME/.hf-cli" ! -user "$(id -un)" -print -quit)" ]
check "no transformers distribution" "$venv/bin/python" -c 'import importlib.metadata; assert not any(d.metadata["Name"] == "transformers" for d in importlib.metadata.distributions())'
check "the venv uses the system Python" "$venv/bin/python" -c 'import sys; assert sys.base_prefix == "/usr"'
check "Python and venv prerequisites are installed" dpkg-query -W python3 python3-venv ca-certificates
check "no skill by default" test ! -e "$HOME/.agents/skills/hf-cli"
check "no Claude skill link by default" test ! -e "$HOME/.claude/skills/hf-cli"
check "daily update checks are disabled" [ "$HF_HUB_DISABLE_UPDATE_CHECK" = 1 ]
check "offline mode is not forced at runtime" [ "${HF_HUB_OFFLINE:-0}" != 1 ]
check "no uv cache in the remote home" test ! -e "$HOME/.cache/uv"
check "no pip cache in the remote home" test ! -e "$HOME/.cache/pip"
check "no token in the remote home" test ! -e "$HOME/.cache/huggingface/token"
# Check root's home too without changing permissions on it.
as_root() { if [[ $(id -u) == 0 ]]; then "$@"; else sudo "$@"; fi; }
check "hf also runs for root" as_root env HF_HUB_DISABLE_UPDATE_CHECK=1 HF_HUB_OFFLINE=1 /usr/local/bin/hf version
check "root holds no uv or pip cache or token" as_root bash -c 'test ! -e /root/.cache/uv && test ! -e /root/.cache/pip && test ! -e /root/.cache/huggingface/token'
check "root ran no code that changed venv ownership" [ -z "$(find "$venv" ! -user "$(id -un)" -print -quit)" ]
# The upstream installer adds a distinctive PATH line; neither user's startup files may hold it.
check "no installer PATH line in startup files" as_root python3 - "$HOME" <<'PY'
import pathlib, sys
for home in {pathlib.Path(sys.argv[1]), pathlib.Path('/root')}:
    for name in ['.bashrc', '.bash_profile', '.profile', '.zshrc', '.config/fish/config.fish']:
        path = home / name
        if path.exists():
            assert 'Added by Hugging Face CLI installer' not in path.read_text(), path
PY
check "the uv volume is mounted" bash -c 'grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* /var/lib/uv " /proc/self/mountinfo'
check "the mounted volume is empty" [ -z "$(ls -A /var/lib/uv)" ]
check "hf works with the mounted volume" hf version
check "anonymous Hub request uses verified TLS" hf models info openai-community/gpt2
reportResults
