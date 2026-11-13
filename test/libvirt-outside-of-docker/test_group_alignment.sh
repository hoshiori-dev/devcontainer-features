#!/usr/bin/env bash
# Scenario "test_group_alignment": libvirt-outside-of-docker with default options on the Ubuntu image, as the remote
# user vscode. Nothing is mounted at /run/libvirt, so the script makes a socket file there with a chosen GID and mode,
# runs the entrypoint's script again, and asserts each case of "Socket group alignment at every start", "Group for the
# socket", "Sockets left to the host's authorization", and "Start record", and that the script leaves /run/libvirt
# as it found it ("Host directory left unchanged"). No daemon listens on the socket, so the start check must fail
# ("Refused").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly SOCKET="/run/libvirt/libvirt-sock"

# Makes the socket file with the GID $1 and the mode $2. python3 is in the image because virt-install needs it.
make_socket() {
  as_root rm -rf /run/libvirt
  as_root mkdir /run/libvirt
  as_root python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "${SOCKET}"
  as_root chown "root:$1" "${SOCKET}"
  as_root chmod "$2" "${SOCKET}"
}

# Prints the numeric owner and group, the mode, the type, and the name of everything under /run/libvirt, and of the
# directory itself. Numeric, because the group's name changes when the entrypoint gives a group the socket's GID.
listing() {
  as_root find /run/libvirt -printf '%U %G %m %y %p\n' | sort
}

# Runs the entrypoint as root and fails unless it exits zero and leaves /run/libvirt as it was.
align() {
  local before after
  before="$(listing)"
  as_root "${LOD_ALIGN}" || return
  after="$(listing)"
  [[ "${before}" == "${after}" ]]
}

group_gid() {
  getent group "$1" | cut -d: -f3
}

is_member() {
  [[ " $(id -nG vscode) " == *" $1 "* ]]
}

groups_before="$(id -nG vscode)"

make_socket 0 0770
check "Socket of the root group: the entrypoint exits zero and changes nothing under /run/libvirt" align
check "Socket of the root group: the remote user's groups are unchanged" test "$(id -nG vscode)" = "${groups_before}"
check "Socket of the root group: the record says so" bash -c "record_field reason | grep -q 'is root (GID 0)'"

make_socket 4242 0777
check "World-writable socket: the entrypoint exits zero and changes nothing under /run/libvirt" align
check "World-writable socket: the remote user's groups are unchanged" test "$(id -nG vscode)" = "${groups_before}"
check "World-writable socket: no group libvirt-host was created" bash -c '! getent group libvirt-host'

make_socket 4242 0770
check "Unused GID: the entrypoint exits zero and changes nothing under /run/libvirt" align
check "Unused GID: libvirt-host has the socket's GID" test "$(group_gid libvirt-host)" = 4242
check "Unused GID: the remote user is a member of libvirt-host" is_member libvirt-host
check "Unused GID: a new process of the remote user can write to the socket" \
  as_root runuser -u vscode -- test -w "${SOCKET}"
check "Start record: it names the socket, its GID, the group, and the result" \
  bash -c "test \"\$(record_field socket)\" = ${SOCKET} && test \"\$(record_field socketGid)\" = 4242 \
    && test \"\$(record_field group)\" = libvirt-host && test \"\$(record_field result)\" = aligned"
check "Start record: the remote user can read it and cannot write it" bash -c "test -r ${LOD_RECORD} -a ! -w ${LOD_RECORD}"

make_socket 4343 0770
check "Host GID changed: the entrypoint exits zero and changes nothing under /run/libvirt" align
check "Host GID changed: libvirt-host has the new GID" test "$(group_gid libvirt-host)" = 4343
check "Host GID changed: the remote user is still a member" is_member libvirt-host

audio_gid="$(group_gid audio)"
make_socket "${audio_gid}" 0770
check "GID of an existing group: the entrypoint exits zero and changes nothing under /run/libvirt" align
check "GID of an existing group: the remote user is a member of that group" is_member audio
check "GID of an existing group: no group was renumbered" \
  test "$(group_gid libvirt-host):$(group_gid audio)" = "4343:${audio_gid}"
check "GID of an existing group: the record names the group and its GID" \
  bash -c "test \"\$(record_field group)\" = audio && record_field reason | grep -q 'existing group audio (GID ${audio_gid})'"

check "Refused: with a socket nobody listens on, the start check exits non-zero" bash -c "! ${LOD_CHECK}"
check "Refused: the start check prints the recorded outcome" \
  bash -c "${LOD_CHECK} 2>&1 | grep -q 'group alignment at this start: aligned'"

groups_now="$(id -nG vscode)"
make_socket 4545 0770
check "Entrypoint not run as root: it exits zero" "${LOD_ALIGN}"
check "Entrypoint not run as root: no group changed" \
  test "$(id -nG vscode):$(group_gid libvirt-host)" = "${groups_now}:4343"

# Root remote user: the settings file, which install.sh wrote, names root for this one run.
as_root cp "${LOD_SETTINGS}" /tmp/lod-settings.backup
printf 'remoteUser=root\n' | as_root tee "${LOD_SETTINGS}" >/dev/null
check "Root remote user: the entrypoint exits zero" align
as_root cp /tmp/lod-settings.backup "${LOD_SETTINGS}"
check "Root remote user: no group was created or changed" \
  test "$(id -nG vscode):$(group_gid libvirt-host)" = "${groups_now}:4343"

as_root rm -rf /run/libvirt
check "No socket: the entrypoint exits zero" as_root "${LOD_ALIGN}"
check "No socket: nothing was created at /run/libvirt" bash -c '! test -e /run/libvirt'
check "No socket: the start check exits zero and names the mount to add" check_reports_no_socket

reportResults
