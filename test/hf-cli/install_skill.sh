#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
skill_dir="${HOME}/.agents/skills/hf-cli"
claude_link="${HOME}/.claude/skills/hf-cli"
# The scenario installs the default version, latest, so the version the skill must name is read from the venv.
installed="$("${venv}/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')"
check "the skill names the installed version" grep -Fq "huggingface_hub v${installed}" "${skill_dir}/SKILL.md"
check "the Claude skill links to the generated skill" test "$(readlink -f "${claude_link}")" = "${skill_dir}"
check "the skill belongs to the remote user" test -z "$(find "${skill_dir}" ! -user "$(id -un)" -print -quit)"
check "the CLI runs" hf version
reportResults
