#!/bin/sh
# Install-twice test: gitleaks is installed with version 8.2.0 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the first. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 8.2.0 and the second selected the default latest.
if [ "${VERSION-}" != "8.2.0" ] || [ "${VERSION__DEFAULT-}" != "latest" ]; then
  printf 'the replace path would not run: it needs version "8.2.0", then "latest", but got "%s", then "%s"\n' \
    "${VERSION-}" "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the latest-release link names.
latest="$(latest_release)"
if [ "${latest}" = "8.2.0" ]; then
  echo 'the replace path would not run: the latest release is 8.2.0, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; latest now: %s\n' "${VERSION}" "${VERSION__DEFAULT}" "${latest}"

# Before gitleaks runs here: the second install ran the installed 8.2.0 as root at build time.
check "neither the remote user's nor root's home holds a file whose name contains gitleaks" \
  no_gitleaks_files_in_homes

check "command -v gitleaks resolves to /usr/local/bin/gitleaks" gitleaks_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than gitleaks whose name contains "gitleaks".
only_one_gitleaks() {
  for only_one_gitleaks_path in /usr/local/bin/*gitleaks* /usr/local/bin/.*gitleaks*; do
    if [ -e "${only_one_gitleaks_path}" ] && [ "${only_one_gitleaks_path}" != "/usr/local/bin/gitleaks" ]; then
      printf '  other file: %s\n' "${only_one_gitleaks_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/gitleaks ]
}
check "/usr/local/bin holds no file other than gitleaks whose name contains gitleaks" only_one_gitleaks

check "gitleaks version reports the version the second install selected" gitleaks_reports_version "${latest}"
check "no temporary directory or staged binary of the installs remains" no_install_leftovers

reportResults
