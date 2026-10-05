#!/usr/bin/env bash
# Default installation on every supported image and architecture.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
check "build-time CLI checks left no auxiliary cache file" test ! -e "${HOME}/.cache/huggingface/.agent_harnesses.json"
# The release PyPI names as latest when the test runs; a release between build and test fails once.
latest="$(
  python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pypi.org/pypi/huggingface_hub/json') as response:
    print(json.load(response)['info']['version'])
PY
)"
installed="$("${venv}/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')"
check "default resolves the latest release" test "${installed}" = "${latest}"
check "hf runs for the remote user" hf version
check "hf is exposed by a root-owned system link" test "$(stat -c '%U %F' /usr/local/bin/hf)" = 'root symbolic link'
check "the link reaches the user's venv" test "$(readlink -f /usr/local/bin/hf)" = "${venv}/bin/hf"
# Succeeds when huggingface_hub itself reports that the standalone installer manages its environment.
environment_is_installer_managed() {
  "${venv}/bin/python" - <<'PY'
from huggingface_hub.utils._runtime import installation_method
assert installation_method() == "hf_installer"
PY
}
check "the environment is installer-managed" environment_is_installer_managed
check "the marker exists" test -f "${venv}/.hf_installer_marker"
check "the installation belongs to the remote user" test -z "$(find "${HOME}/.hf-cli" ! -user "$(id -un)" -print -quit)"
# Succeeds when the venv holds no distribution named transformers.
no_transformers_distribution() {
  "${venv}/bin/python" - <<'PY'
import importlib.metadata
assert not any(d.metadata["Name"] == "transformers" for d in importlib.metadata.distributions())
PY
}
check "no transformers distribution" no_transformers_distribution
check "the venv uses the system Python" "${venv}/bin/python" -c 'import sys; assert sys.base_prefix == "/usr"'
check "Python and venv prerequisites are installed" dpkg-query -W python3 python3-venv ca-certificates
check "no skill by default" test ! -e "${HOME}/.agents/skills/hf-cli"
check "no Claude skill link by default" test ! -e "${HOME}/.claude/skills/hf-cli"
check "daily update checks are disabled" test "${HF_HUB_DISABLE_UPDATE_CHECK-}" = 1
check "offline mode is not forced at runtime" test "${HF_HUB_OFFLINE:-0}" != 1
check "no uv cache in the remote home" test ! -e "${HOME}/.cache/uv"
check "no pip cache in the remote home" test ! -e "${HOME}/.cache/pip"
check "no token in the remote home" test ! -e "${HOME}/.cache/huggingface/token"
# Runs a command as root, so root's home is checked without changing its permissions.
as_root() {
  if [[ "$(id -u)" == 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
check "hf also runs for root" as_root env HF_HUB_DISABLE_UPDATE_CHECK=1 HF_HUB_OFFLINE=1 /usr/local/bin/hf version
# Succeeds when root's home holds no uv cache, no pip cache, and no Hugging Face token.
root_holds_no_cache_or_token() {
  as_root bash -c \
    'test ! -e /root/.cache/uv && test ! -e /root/.cache/pip && test ! -e /root/.cache/huggingface/token'
}
check "root holds no uv or pip cache or token" root_holds_no_cache_or_token
check "root ran no code that changed venv ownership" test -z "$(find "${venv}" ! -user "$(id -un)" -print -quit)"
# Succeeds when no startup file of the remote user or of root holds the comment that the upstream installer writes
# above the PATH line it adds.
no_installer_path_line_in_startup_files() {
  as_root python3 - "${HOME}" <<'PY'
import pathlib, sys
for home in {pathlib.Path(sys.argv[1]), pathlib.Path('/root')}:
    for name in ['.bashrc', '.bash_profile', '.profile', '.zshrc', '.config/fish/config.fish']:
        path = home / name
        if path.exists():
            assert 'Added by Hugging Face CLI installer' not in path.read_text(), path
PY
}
check "no installer PATH line in startup files" no_installer_path_line_in_startup_files
# Succeeds when the INSTALLER record of the venv's huggingface_hub distribution names the tool $1.
packages_were_installed_by() {
  "${venv}/bin/python" - "$1" <<'PY'
import importlib.metadata, sys
assert importlib.metadata.distribution("huggingface_hub").read_text("INSTALLER").strip() == sys.argv[1]
PY
}
check "packages were installed by pip without uv" packages_were_installed_by pip
check "uv was not installed" bash -c '! command -v uv'
no_uv_settings() {
  [[ ! -e /var/lib/uv && -z "${UV_PYTHON_INSTALL_DIR:-}" && -z "${UV_CACHE_DIR:-}" ]]
}
check "no uv volume or environment was added" no_uv_settings
check "anonymous Hub request uses verified TLS" hf models info openai-community/gpt2
reportResults
