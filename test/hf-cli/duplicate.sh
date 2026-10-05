#!/usr/bin/env bash
# The tooling installs the feature with version 1.33.0 and the skill, then with the defaults: latest, without the skill.
# It passes the first install's version in as VERSION.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

venv="${HOME}/.hf-cli/venv"
skill_dir="${HOME}/.agents/skills/hf-cli"
# The release PyPI names as latest when the test runs, which the second install resolved; a release between build and
# test fails once.
latest="$(
  python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pypi.org/pypi/huggingface_hub/json') as response:
    print(json.load(response)['info']['version'])
PY
)"
installed="$("${venv}/bin/python" -c 'import importlib.metadata; print(importlib.metadata.version("huggingface_hub"))')"
check "the later version replaces the first" test "${installed}" = "${latest}"
# Succeeds when the venv holds exactly one distribution named huggingface_hub.
only_one_huggingface_hub_distribution() {
  "${venv}/bin/python" - <<'PY'
import importlib.metadata
assert len([d for d in importlib.metadata.distributions() if d.metadata["Name"] == "huggingface_hub"]) == 1
PY
}
check "only one huggingface_hub distribution remains" only_one_huggingface_hub_distribution
check "/usr/local/bin/hf runs the later release" hf version
check "the disabled skill keeps its earlier version" grep -Fq "huggingface_hub v${VERSION}" "${skill_dir}/SKILL.md"
check "the Claude link remains" test "$(readlink -f "${HOME}/.claude/skills/hf-cli")" = "${skill_dir}"
check "all venv files belong to the remote user" test -z "$(find "${venv}" ! -user "$(id -un)" -print -quit)"
check "no token is written" test ! -e "${HOME}/.cache/huggingface/token"
if [[ "$(id -u)" != 0 ]]; then check "root has no token" sudo test ! -e /root/.cache/huggingface/token; fi
reportResults
