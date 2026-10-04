#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
version=$("$HOME/.hf-cli/venv/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')
check "the skill names the installed version" grep -Fq "huggingface_hub v$version" "$HOME/.agents/skills/hf-cli/SKILL.md"
check "the Claude skill links to the generated skill" [ "$(readlink -f "$HOME/.claude/skills/hf-cli")" = "$HOME/.agents/skills/hf-cli" ]
check "the skill belongs to the remote user" [ -z "$(find "$HOME/.agents/skills/hf-cli" ! -user "$(id -un)" -print -quit)" ]
check "the CLI runs" hf version
reportResults
