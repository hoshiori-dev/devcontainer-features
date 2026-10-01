#!/usr/bin/env bash
# Scenario backend_nfs (scenarios.json): spec scenario "Only the NFS backend selected", on an image
# that ships no hf-mount-fuse; with the mount dependencies enabled, only the NFS helper is installed.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

has_mount_nfs() {
  [ -x /sbin/mount.nfs ] || [ -x /usr/sbin/mount.nfs ] || command -v mount.nfs >/dev/null
}

no_hf_mount_fuse() {
  [ ! -e /usr/local/bin/hf-mount-fuse ] && ! command -v hf-mount-fuse >/dev/null
}

no_fusermount3() {
  ! command -v fusermount3 >/dev/null
}

check "hf-mount is installed" test -x /usr/local/bin/hf-mount
check "hf-mount-nfs is installed" test -x /usr/local/bin/hf-mount-nfs
check "hf-mount-fuse is not installed" no_hf_mount_fuse
check "hf-mount --version succeeds" hf-mount --version
check "mount.nfs is present" has_mount_nfs
check "fusermount3 was not installed" no_fusermount3

reportResults
