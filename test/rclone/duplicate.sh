#!/bin/sh
# Install-twice test: rclone is installed with version 1.70.0 and installMountDependencies true (VERSION,
# INSTALLMOUNTDEPENDENCIES), then with the defaults latest and false (VERSION__DEFAULT,
# INSTALLMOUNTDEPENDENCIES__DEFAULT), so the second install replaces the binary and the completions and keeps fuse3.
# POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 1.70.0 and the second selected the default latest; the
# package path only when the first enabled the mount dependencies and the second did not.
if [ "${VERSION-}" != "1.70.0" ] || [ "${VERSION__DEFAULT-}" != "latest" ] \
  || [ "${INSTALLMOUNTDEPENDENCIES-}" != "true" ] || [ "${INSTALLMOUNTDEPENDENCIES__DEFAULT-}" != "false" ]; then
  printf 'the paths under test would not run: expected version 1.70.0 then latest and installMountDependencies' >&2
  printf ' true then false, got %s then %s and %s then %s\n' "${VERSION-}" "${VERSION__DEFAULT-}" \
    "${INSTALLMOUNTDEPENDENCIES-}" "${INSTALLMOUNTDEPENDENCIES__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the version file names.
latest="$(latest_release)"
if [ "${latest}" = "1.70.0" ]; then
  echo 'the replace path would not run: the newest release is 1.70.0, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s, %s; second install: %s, %s; newest now: %s\n' "${VERSION}" \
  "${INSTALLMOUNTDEPENDENCIES}" "${VERSION__DEFAULT}" "${INSTALLMOUNTDEPENDENCIES__DEFAULT}" "${latest}"

check "command -v rclone resolves to /usr/local/bin/rclone" rclone_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than rclone whose name contains "rclone".
only_one_rclone() {
  for only_one_rclone_path in /usr/local/bin/*rclone* /usr/local/bin/.*rclone*; do
    if [ -e "${only_one_rclone_path}" ] && [ "${only_one_rclone_path}" != "/usr/local/bin/rclone" ]; then
      printf '  other file: %s\n' "${only_one_rclone_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/rclone ]
}
check "/usr/local/bin holds no file other than rclone whose name contains rclone" only_one_rclone
check "rclone version reports the release the second install selected" rclone_reports_version "${latest}"
check "the completion files equal what the release of the second install generates" completions_match
check "fusermount3 from the first install is still on PATH, owned by root with the set-user-ID bit" \
  fusermount3_setuid_on_path
check "no temporary directory or staged file of the installs remains" no_install_leftovers

reportResults
