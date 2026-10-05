#!/usr/bin/env bash
# Scenario dependencies_disabled (scenarios.json): spec scenario "Dependencies disabled", on an image that ships
# neither mount.nfs nor fusermount3.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

for binary in hf-mount hf-mount-nfs hf-mount-fuse; do
  check "${binary} is installed" test -x "/usr/local/bin/${binary}"
done
check "hf-mount --version succeeds" hf-mount --version

no_mount_nfs() {
  [[ ! -e /sbin/mount.nfs && ! -e /usr/sbin/mount.nfs ]] && ! command -v mount.nfs >/dev/null
}
check "mount.nfs is not present" no_mount_nfs

no_fusermount3() {
  ! command -v fusermount3 >/dev/null
}
check "fusermount3 is not present" no_fusermount3

reportResults
