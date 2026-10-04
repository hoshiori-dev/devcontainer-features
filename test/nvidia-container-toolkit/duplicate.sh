#!/usr/bin/env bash
# Install-twice test: nvidia-container-toolkit is installed first with the non-default options the CLI
# picks (version = the proposals entry after latest, configureDocker disabled), then with the defaults
# (version latest, configureDocker enabled). Option values arrive as <OPTION> and <OPTION>__DEFAULT.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

CANDIDATE="$(newest_candidate || true)"

# Without this the test would not change the version: the proposals entry after latest must be an exact
# release older than the newest one in the repository (design.md, Goals).
first_install_changed_version() {
  if [[ -z "$CANDIDATE" || "${VERSION__DEFAULT:-}" != "latest" || "${VERSION:-}-1" == "$CANDIDATE" ]]; then
    echo "first install version '${VERSION:-}', default '${VERSION__DEFAULT:-}', newest '$CANDIDATE'" >&2
    return 1
  fi
}

check "the first install received version ${VERSION:-unset}, not the newest (${CANDIDATE:-none})" \
  first_install_changed_version
check "all four packages end at the newest version the second install selected" packages_at "$CANDIDATE"
check "nvidia-ctk reports the newest version" ctk_reports "${CANDIDATE%-*}"
check "NVIDIA's repository is defined once" repository_defined_once
check "the source definition names NVIDIA's stable repository, signature checks, and the local key" \
  repository_file_is_expected
check "the key file holds only NVIDIA's pinned key" key_is_pinned
check "no temporary GNUPGHOME remains" no_temporary_gnupghome
check "no daemon.json is created without a Docker daemon" no_daemon_json

reportResults
