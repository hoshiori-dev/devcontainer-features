#!/usr/bin/env bash
# Install-twice test: godot is installed with version 4.6.3 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the executable of the first.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/headless.sh"

# The replace path runs only when the first install was 4.6.3 and the second selected the default latest.
if [[ "${VERSION-}" != 4.6.3 || "${VERSION__DEFAULT-}" != latest ]]; then
  printf 'the replace path would not run: expected version 4.6.3 then latest, got %s then %s\n' "${VERSION-}" \
    "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the latest-release link names; a release published
# between build and test fails the comparison once.
latest_tag="$(latest_release_tag)"
if [[ "${latest_tag}" == 4.6.3-stable ]]; then
  echo 'the replace path would not run: the latest release is 4.6.3, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; the latest-release link names %s\n' "${VERSION}" \
  "${VERSION__DEFAULT}" "${latest_tag}"

check "godot --version reports the version the second install selected" godot_reports_version "${latest_tag%-stable}"
check "command -v godot resolves, following symbolic links, to /usr/local/bin/godot" godot_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than godot whose name starts with "godot" or ".godot".
only_one_godot() {
  local path
  for path in /usr/local/bin/godot* /usr/local/bin/.godot*; do
    if [[ -e "${path}" && "${path}" != /usr/local/bin/godot ]]; then
      printf '  other file: %s\n' "${path}"
      return 1
    fi
  done
  [[ -f /usr/local/bin/godot ]]
}
check "/usr/local/bin holds no file other than godot whose name starts with godot or .godot" only_one_godot
check "no temporary directory, archive, or staged executable of the installs remains" no_install_residue

reportResults
