#!/usr/bin/env bash
# Scenario test_backend_nfs (scenarios.json): spec scenario "Only the NFS backend selected", on an image that ships no
# hf-mount-fuse; with the mount dependencies enabled, only the NFS helper is installed.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "hf-mount is installed" test -x /usr/local/bin/hf-mount
check "hf-mount-nfs is installed" test -x /usr/local/bin/hf-mount-nfs

no_hf_mount_fuse() {
  [[ ! -e /usr/local/bin/hf-mount-fuse ]] && ! command -v hf-mount-fuse >/dev/null
}
check "hf-mount-fuse is not installed" no_hf_mount_fuse
check "hf-mount --version succeeds" hf-mount --version

has_mount_nfs() {
  if [[ -x /sbin/mount.nfs || -x /usr/sbin/mount.nfs ]]; then return 0; fi
  command -v mount.nfs >/dev/null
}
check "mount.nfs is present in /sbin, /usr/sbin, or on PATH" has_mount_nfs

# debian:12 ships no fusermount3, so one on PATH would have come with this install.
no_fusermount3() {
  ! command -v fusermount3 >/dev/null
}
check "the mount helper of the FUSE backend, which is not selected, is not installed: fusermount3 is not on PATH" \
  no_fusermount3

reportResults
