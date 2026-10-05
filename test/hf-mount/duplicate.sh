#!/usr/bin/env bash
# Install-twice test: the tooling installs hf-mount once with non-default options (the first proposal of `version` that
# is not the default, `backend` nfs, `installMountDependencies` false) and once with the defaults. The first install's
# option values arrive as <OPTION> and the defaults as <OPTION>__DEFAULT. Scenario "Non-default options, then the
# defaults". It makes no network request.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The scenario needs a first install that pinned a release, selected only the NFS backend, and disabled the mount
# dependencies. A reordered enum or a changed proposal changes what the tooling passes, and the checks below would
# then show something else, so the test stops here.
if [[ "${VERSION-}" == "${VERSION__DEFAULT-}" ]]; then
  printf 'the first install must pin a release, but its version was "%s", the default\n' "${VERSION-}" >&2
  exit 1
fi
if [[ "${BACKEND-}" != nfs ]]; then
  printf 'the first install must select backend "nfs", but its backend was "%s"\n' "${BACKEND-}" >&2
  exit 1
fi
if [[ "${INSTALLMOUNTDEPENDENCIES-}" != false ]]; then
  printf 'the first install must set installMountDependencies to false, but it was "%s"\n' \
    "${INSTALLMOUNTDEPENDENCIES-}" >&2
  exit 1
fi

for binary in hf-mount hf-mount-nfs hf-mount-fuse; do
  check "${binary} is present" test -x "/usr/local/bin/${binary}"
done
check "hf-mount --version succeeds" hf-mount --version

# `$1 --version` and `hf-mount --version` both succeed and print the same line. The later version is read from the
# daemon at run time, not written as a literal: the second install followed `latest`, which can move between the build
# and the test. Every `backend` value selects the daemon, so the second install replaced it. For hf-mount-nfs this
# tells a replaced binary from a kept one only once upstream's latest release is newer than the proposal the first
# install pinned; until then both installs bring the same release.
same_release_as_daemon() {
  local backend_version
  local daemon_version
  backend_version="$("$1" --version)" || return
  daemon_version="$(hf-mount --version)" || return
  [[ "${backend_version}" == "${daemon_version}" ]]
}
check "the later version applies to hf-mount-nfs, which the later backend selects" same_release_as_daemon hf-mount-nfs
check "the later version applies to hf-mount-fuse, which the later backend selects" same_release_as_daemon hf-mount-fuse

has_mount_nfs() {
  if [[ -x /sbin/mount.nfs || -x /usr/sbin/mount.nfs ]]; then return 0; fi
  command -v mount.nfs >/dev/null
}
check "mount.nfs is present in /sbin, /usr/sbin, or on PATH" has_mount_nfs
check "fusermount3 is on PATH" command -v fusermount3

reportResults
