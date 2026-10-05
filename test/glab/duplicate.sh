#!/bin/sh
# Install-twice test: glab is installed with version 1.47.0 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the first. POSIX sh, because alpine:3.24 ships no bash.
set -eu

readonly LATEST_URL="https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest"

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 1.47.0 and the second selected the default latest.
if [ "${VERSION-}" != "1.47.0" ] || [ "${VERSION__DEFAULT-}" != "latest" ]; then
  printf 'the replace path would not run: it needs version "1.47.0", then "latest", but got "%s", then "%s"\n' \
    "${VERSION-}" "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# The release the permanent link to the latest release names when the test runs, read as install.sh reads it,
# without following the redirect; a release between build and test fails once.
location="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 \
  --head --output /dev/null --write-out '%{redirect_url}' "${LATEST_URL}")"
if [ -z "${location}" ]; then
  printf '%s did not redirect to a release\n' "${LATEST_URL}" >&2
  exit 1
fi
# The same parsing as install.sh: drop a query or fragment and a trailing slash, keep the last segment without "v".
latest="${location%%[?#]*}"
latest="${latest%/}"
latest="${latest##*/}"
latest="${latest#v}"
if [ "${latest}" = "1.47.0" ]; then
  printf 'the replace path would not run: the latest release is 1.47.0, the version of the first install\n' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; latest now: %s\n' "${VERSION}" "${VERSION__DEFAULT}" "${latest}"

# Before glab runs here: the second install ran the installed 1.47.0 as root at build time, and 1.47.0 writes its
# configuration on every call.
check "neither the remote user's nor root's home holds a glab configuration directory" no_glab_config

check "command -v glab resolves to /usr/local/bin/glab" glab_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than glab whose name contains "glab".
only_one_glab() {
  for only_one_glab_path in /usr/local/bin/*glab* /usr/local/bin/.*glab*; do
    if [ -e "${only_one_glab_path}" ] && [ "${only_one_glab_path}" != "/usr/local/bin/glab" ]; then
      printf '  other file: %s\n' "${only_one_glab_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/glab ]
}
check "/usr/local/bin holds no file other than glab whose name contains glab" only_one_glab

check "glab --version reports the version the second install selected" glab_reports_version "${latest}"
check "no temporary directory or staged binary of the installs remains" no_install_leftovers

reportResults
