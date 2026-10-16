#!/bin/sh
# Install-twice test: betterleaks is installed with version 1.0.1 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the first. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 1.0.1 and the second selected the default latest.
if [ "${VERSION-}" != "1.0.1" ] || [ "${VERSION__DEFAULT-}" != "latest" ]; then
  printf 'the replace path would not run: it needs version "1.0.1", then "latest", but got "%s", then "%s"\n' \
    "${VERSION-}" "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the latest-release link names.
latest="$(latest_release)"
if [ "${latest}" = "1.0.1" ]; then
  echo 'the replace path would not run: the latest release is 1.0.1, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; latest now: %s\n' "${VERSION}" "${VERSION__DEFAULT}" "${latest}"

# Before betterleaks runs here: the second install ran the installed 1.0.1 as root at build time.
check "neither the remote user's nor root's home holds a file whose name contains betterleaks" \
  no_betterleaks_files_in_homes

check "command -v betterleaks resolves to /usr/local/bin/betterleaks" betterleaks_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than betterleaks whose name contains "betterleaks".
only_one_betterleaks() {
  for only_one_betterleaks_path in /usr/local/bin/*betterleaks* /usr/local/bin/.*betterleaks*; do
    if [ -e "${only_one_betterleaks_path}" ] && [ "${only_one_betterleaks_path}" != "/usr/local/bin/betterleaks" ]; then
      printf '  other file: %s\n' "${only_one_betterleaks_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/betterleaks ]
}
check "/usr/local/bin holds no file other than betterleaks whose name contains betterleaks" only_one_betterleaks

check "betterleaks version reports the version the second install selected" betterleaks_reports_version "${latest}"
check "no temporary directory or staged binary of the installs remains" no_install_leftovers

reportResults
