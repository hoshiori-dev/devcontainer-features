# shellcheck shell=bash
# Assertions shared by default, duplicate, and scenario tests.
readonly TOOL_ENV="/usr/local/share/uv/tools/google-colab-cli"

installed_release() {
  "${TOOL_ENV}/bin/python" -I -c 'from importlib.metadata import version; print(version("google-colab-cli"))'
}

reports_release() {
  local output
  output="$(colab version)"
  [[ "${output}" == *"$1"* ]] && [[ "$(installed_release)" == "$1" ]]
}

latest_release() {
  # latest is a build-time selection; a release between build and test can require a rerun.
  "${TOOL_ENV}/bin/python" -I -c '
import json, urllib.request
from packaging.version import Version
with urllib.request.urlopen("https://pypi.org/pypi/google-colab-cli/json") as response:
    data = json.load(response)
stable = [Version(v) for v, files in data["releases"].items()
          if files and not Version(v).is_prerelease and not Version(v).is_devrelease
          and any(not f["yanked"] for f in files)]
print(max(stable))'
}

image_interpreter() {
  "${TOOL_ENV}/bin/python" -I -c '
import sys
from pathlib import Path
assert sys.version_info[:2] == (3, 12)
assert Path(sys.executable).resolve().is_relative_to("/usr/local/share/uv/python")'
}

not_world_writable() {
  # Linux symlinks report mode 777; access is controlled by their targets and containing directories.
  [[ -z "$(find "${TOOL_ENV}" /usr/local/share/uv/python \( -type f -o -type d \) -perm -0002 -print -quit)" ]]
}

one_path_entry() {
  local entry
  local count=0
  local entries
  IFS=: read -r -a entries <<<"${PATH}"
  for entry in "${entries[@]}"; do
    if [[ "${entry}" == /usr/local/share/uv/bin ]]; then count=$((count + 1)); fi
  done
  [[ "${count}" == 1 ]]
}
