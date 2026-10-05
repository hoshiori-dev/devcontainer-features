#!/usr/bin/env bash
# Scenario backend_fuse (scenarios.json): spec scenario "Only the FUSE backend selected", on an image that ships no
# hf-mount-nfs; with the mount dependencies enabled, only the FUSE helper is installed.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

check "hf-mount is installed" test -x /usr/local/bin/hf-mount
check "hf-mount-fuse is installed" test -x /usr/local/bin/hf-mount-fuse

no_hf_mount_nfs() {
  [[ ! -e /usr/local/bin/hf-mount-nfs ]] && ! command -v hf-mount-nfs >/dev/null
}
check "hf-mount-nfs is not installed" no_hf_mount_nfs
check "hf-mount --version succeeds" hf-mount --version
check "fusermount3 is on PATH" command -v fusermount3

# debian:12 ships no mount.nfs, so one in /sbin, /usr/sbin, or on PATH would have come with this install.
no_mount_nfs() {
  [[ ! -e /sbin/mount.nfs && ! -e /usr/sbin/mount.nfs ]] && ! command -v mount.nfs >/dev/null
}
check "the mount helper of the NFS backend, which is not selected, is not installed: mount.nfs is not present" \
  no_mount_nfs

reportResults
