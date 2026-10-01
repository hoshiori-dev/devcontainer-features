#!/usr/bin/env bash
# Install-twice test: hf-mount is installed once with non-default options (the first proposal of
# `version` that is not the default, `backend` nfs, `installMountDependencies` false) and once with
# the defaults. Option values arrive as <OPTION> and <OPTION>__DEFAULT env vars. Scenario
# "Non-default options, then the defaults". It makes no network request.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

same_release_as_daemon() {
  [ "$("$1" --version)" = "$(hf-mount --version)" ]
}

has_mount_nfs() {
  [ -x /sbin/mount.nfs ] || [ -x /usr/sbin/mount.nfs ] || command -v mount.nfs >/dev/null
}

check "the first install pinned a release" test "$VERSION" != "$VERSION__DEFAULT"
check "the first install selected only the NFS backend" test "$BACKEND" = nfs
check "the first install disabled the mount dependencies" test "$INSTALLMOUNTDEPENDENCIES" = false

for binary in hf-mount hf-mount-nfs hf-mount-fuse; do
  check "$binary is present" test -x "/usr/local/bin/$binary"
done
check "hf-mount --version succeeds" hf-mount --version
# The second install replaces the daemon and both backends, so all three report one release. For
# hf-mount-nfs this tells a replaced binary from a kept one only once upstream's latest release is
# newer than the proposal the first install pinned; until then both installs bring the same release.
check "hf-mount-nfs reports the daemon's release" same_release_as_daemon hf-mount-nfs
check "hf-mount-fuse reports the daemon's release" same_release_as_daemon hf-mount-fuse
check "mount.nfs is present" has_mount_nfs
check "fusermount3 is on PATH" command -v fusermount3

reportResults
