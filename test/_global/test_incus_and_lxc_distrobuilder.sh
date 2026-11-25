#!/usr/bin/env bash
# Global scenario "test_incus_and_lxc_distrobuilder": incus and lxc-distrobuilder (with vmSupport) installed together
# on the Ubuntu 24.04 dev container image, for the remote user vscode. An image that distrobuilder builds is imported
# into Incus and started as an instance, and, because incus makes the container privileged, distrobuilder also builds
# a virtual machine image (lxc-distrobuilder's spec, "Virtual machine image in a privileged container").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INSTANCE="built"

work_dir="$(mktemp -d)"
cat >"${work_dir}/alpine.yaml" <<'DEFINITION'
image:
  distribution: alpinelinux
  release: "3.22"
  description: Alpine Linux {{ image.release }} built by the global feature test

source:
  downloader: alpinelinux-http
  url: https://dl-cdn.alpinelinux.org/alpine/

packages:
  manager: apk
  update: false
  cleanup: false
DEFINITION

# The instance reaches the state RUNNING within 30 seconds.
instance_runs() {
  local waited
  for ((waited = 0; waited < 30; waited++)); do
    if [[ "$(incus list "${INSTANCE}" --format csv --columns s)" == RUNNING ]]; then return 0; fi
    sleep 1
  done
  incus info "${INSTANCE}" --show-log
  return 1
}

check "the start check of incus exits zero" /usr/local/share/incus-feature/check.sh
check "distrobuilder builds a container image for Incus" \
  sudo distrobuilder build-incus "${work_dir}/alpine.yaml" "${work_dir}/container"
check "the image is imported into Incus" \
  incus image import "${work_dir}/container/incus.tar.xz" "${work_dir}/container/rootfs.squashfs" --alias "${INSTANCE}"
# incus launch reads an instance configuration from standard input when that is not a terminal.
check "an instance of the built image is launched" bash -c "incus launch ${INSTANCE} ${INSTANCE} </dev/null"
check "the instance runs" instance_runs
check "the instance is the Alpine release the definition names" \
  bash -c "incus exec ${INSTANCE} -- cat /etc/alpine-release | grep -q '^3\.22\.'"
check "the instance is removed" incus delete --force "${INSTANCE}"
check "in the privileged container, distrobuilder builds a virtual machine image" \
  sudo distrobuilder build-incus --vm "${work_dir}/alpine.yaml" "${work_dir}/vm"
check "the virtual machine image holds a disk image" test -s "${work_dir}/vm/disk.qcow2"

reportResults
