#!/usr/bin/env bash
# The CLI test installs 1.33.0 with the skill, then latest without the skill.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
venv="$HOME/.hf-cli/venv"
latest=$(python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pypi.org/pypi/huggingface_hub/json') as response:
    print(json.load(response)['info']['version'])
PY
)
check "the later version replaces the first" "$venv/bin/python" -c 'import importlib.metadata, sys; assert importlib.metadata.version("huggingface_hub") == sys.argv[1]' "$latest"
check "only one huggingface_hub distribution remains" "$venv/bin/python" -c 'import importlib.metadata; assert len([d for d in importlib.metadata.distributions() if d.metadata["Name"] == "huggingface_hub"]) == 1'
check "the system link runs the later CLI" hf version
check "the disabled skill keeps its earlier version" grep -Fq "huggingface_hub v${VERSION}" "$HOME/.agents/skills/hf-cli/SKILL.md"
check "the Claude link remains" [ "$(readlink -f "$HOME/.claude/skills/hf-cli")" = "$HOME/.agents/skills/hf-cli" ]
check "all venv files belong to the remote user" [ -z "$(find "$venv" ! -user "$(id -un)" -print -quit)" ]
check "no token is written" test ! -e "$HOME/.cache/huggingface/token"
if [[ $(id -u) != 0 ]]; then check "root has no token" sudo test ! -e /root/.cache/huggingface/token; fi
reportResults
