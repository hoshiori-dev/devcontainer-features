#!/usr/bin/env bash
# Install-twice test: godot-dotnet is installed with version 4.6.3 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install switches the link to a new release directory and removes the first.
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
check "/usr/local/bin/godot is still the symbolic link into /opt/godot-dotnet" godot_links_into_release
check "/opt/godot-dotnet holds the marker and exactly one release directory, the one the link points into" \
  one_release_directory

# No entry of $1 other than $2 has a name starting with one of the prefixes that follow.
no_other_entry() {
  local directory="$1"
  local keep="$2"
  local prefix
  local path
  shift 2
  for prefix in "$@"; do
    for path in "${directory}/${prefix}"*; do
      if [[ (-e "${path}" || -L "${path}") && "${path}" != "${directory}/${keep}" ]]; then
        printf '  other entry: %s\n' "${path}"
        return 1
      fi
    done
  done
}
check "/opt holds no entry other than godot-dotnet whose name starts with godot-dotnet or .godot-dotnet" \
  no_other_entry /opt godot-dotnet godot-dotnet .godot-dotnet
check "/usr/local/bin holds no entry other than godot whose name starts with godot or .godot" \
  no_other_entry /usr/local/bin godot godot .godot
check "no temporary directory, temporary link, or other release directory of the installs remains" no_install_residue

reportResults
