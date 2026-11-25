#!/bin/sh
# Install-twice test: packer is installed with version 1.15.4 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the binary. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 1.15.4 and the second selected the default latest.
if [ "${VERSION-}" != "1.15.4" ] || [ "${VERSION__DEFAULT-}" != "latest" ]; then
  printf 'the replace path would not run: expected version 1.15.4 then latest, got %s then %s\n' \
    "${VERSION-}" "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the Checkpoint service reports as current.
latest="$(latest_release)"
if [ "${latest}" = "1.15.4" ]; then
  echo 'the replace path would not run: the current release is 1.15.4, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; latest now: %s\n' "${VERSION}" "${VERSION__DEFAULT}" "${latest}"

check "command -v packer resolves to /usr/local/bin/packer" packer_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than packer whose name contains "packer".
only_one_packer() {
  for only_one_packer_path in /usr/local/bin/*packer* /usr/local/bin/.*packer*; do
    if [ -e "${only_one_packer_path}" ] && [ "${only_one_packer_path}" != "/usr/local/bin/packer" ]; then
      printf '  other file: %s\n' "${only_one_packer_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/packer ]
}
check "/usr/local/bin holds no file other than packer whose name contains packer" only_one_packer
check "packer version reports the release the second install selected" packer_reports_version "${latest}"
check "no temporary directory or staged file of the installs remains" no_install_leftovers

reportResults
