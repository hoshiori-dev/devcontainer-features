#!/usr/bin/env bash
# Install-twice test: lxc-distrobuilder is installed first with the non-default options the CLI picks (version 3.3.1,
# vmSupport true, windowsSupport true), then with the defaults. Option values arrive as VERSION, VMSUPPORT,
# WINDOWSSUPPORT, and their __DEFAULT counterparts. The later install's release replaces the earlier one, and the
# tools the first install added stay.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# The replace path runs only when the first install was 3.3.1 and the second selected the default latest.
check "the first install received 3.3.1, true, and true, the second the defaults" \
  test "${VERSION:-}:${VMSUPPORT:-}:${WINDOWSSUPPORT:-}:${VERSION__DEFAULT:-}:${VMSUPPORT__DEFAULT:-}" \
  = 3.3.1:true:true:latest:false

# The release the latest-release link names when the test runs; a release between build and test fails once.
latest="$(latest_release)"

check "the latest release is not 3.3.1, so the second install replaced the first" test "${latest}" != 3.3.1
check "distrobuilder --version as root prints the latest release, which is also the recorded one" \
  reports_version "${latest}"
check "the tools of vmSupport, which the first install added, are still on root's PATH" \
  on_root_path mkfs.btrfs mkfs.vfat mkfs.ext4 sgdisk qemu-img udevadm
check "the tools of windowsSupport, which the first install added, are still on PATH" \
  on_root_path hivexregedit wimlib-imagex genisoimage
check "/usr/local/bin holds no staged executable of an install" \
  bash -c '! compgen -G "/usr/local/bin/.lxc-distrobuilder.*"'
check "no Go toolchain is left in the image" no_toolchain_left
check "root builds a container image with distrobuilder build-incus" builds_container_image

reportResults
