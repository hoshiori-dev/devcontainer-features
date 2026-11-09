#!/bin/sh
# Scenario test_mount_dependencies: the Ubuntu base image as vscode with installMountDependencies true. Shows that
# fusermount3 is installed for the remote user, and that the started container runs no rclone and mounts nothing, with
# /etc/fuse.conf left to the user. POSIX sh, like the other rclone tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "fusermount3 is on the remote user's PATH, owned by root with the set-user-ID bit" fusermount3_setuid_on_path

no_rclone_process() {
  for no_rclone_process_comm in /proc/[0-9]*/comm; do
    if [ "$(cat "${no_rclone_process_comm}" 2>/dev/null || true)" = "rclone" ]; then
      printf '  rclone runs: %s\n' "${no_rclone_process_comm}"
      return 1
    fi
  done
}
check "no rclone process runs in the started container" no_rclone_process

no_fuse_mount() {
  no_fuse_mounts="$(awk '$3 ~ /^fuse/' /proc/mounts)"
  if [ -n "${no_fuse_mounts}" ]; then
    printf '  mounted:\n%s\n' "${no_fuse_mounts}"
    return 1
  fi
}
check "no FUSE filesystem is mounted" no_fuse_mount
check "/etc/fuse.conf holds no uncommented user_allow_other line" \
  sh -c '! grep -q -E "^[[:space:]]*user_allow_other" /etc/fuse.conf'
check "rclone version reports the release the version file names" rclone_reports_version "$(latest_release)"

reportResults
