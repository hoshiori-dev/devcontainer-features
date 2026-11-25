#!/usr/bin/env bash
# Scenario "test_tool_options": lxc-distrobuilder installed on debian:13 with version v3.4.0, vmSupport true, and
# windowsSupport true. The release with its leading "v" removed is installed ("Explicit version", "Leading v
# accepted"), the tools of both options are present ("vmSupport enabled", "windowsSupport enabled"), and a virtual
# machine image still cannot be built, because the container is not privileged ("Virtual machine image without
# privilege").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# `distrobuilder build-incus --vm` fails for lack of a loop device, and writes no disk image.
vm_image_fails_for_loop_device() {
  local out output
  local status=0
  out="$(mktemp -d)"
  output="$(as_root "${DB_TARGET}" build-incus --vm "$(dirname "$0")/alpine.yaml" "${out}" 2>&1)" || status=$?
  printf '%s\n' "${output}" | tail -n 5
  ((status != 0)) || return
  grep -q 'loop device' <<<"${output}" || return
  [[ ! -e "${out}/disk.qcow2" ]] || return
  as_root rm -rf "${out}"
}

check "distrobuilder --version as root prints 3.4.0, which is also the recorded release" reports_version 3.4.0
check "the tools of vmSupport are on root's PATH" on_root_path mkfs.btrfs mkfs.vfat mkfs.ext4 sgdisk qemu-img udevadm
check "the tools of windowsSupport are on PATH" on_root_path hivexregedit wimlib-imagex genisoimage
check "the container holds SYS_ADMIN and is not privileged" holds_sys_admin_only
check "root builds a container image with distrobuilder build-incus" builds_container_image
check "a virtual machine image fails for lack of a loop device" vm_image_fails_for_loop_device

reportResults
