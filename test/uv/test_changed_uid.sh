#!/bin/sh
# Scenario "test_changed_uid": group access after the dev container tooling changed the remote user's UID, on Alpine
# ("Changed UID", "Volume that fits"). POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

readonly VOLUME_DIR="/var/lib/uv"
readonly SHARE_DIR="/usr/local/share/uv"
readonly REPAIR="/usr/local/share/uv-feature/repair-volume"
# The UID test_changed_uid/Dockerfile gives the remote user at build time.
readonly BUILD_UID=23456

owns_neither_location() {
  owns_neither_location_uid="$(id -u)"
  [ "$(stat -c %u "${VOLUME_DIR}")" != "${owns_neither_location_uid}" ] \
    && [ "$(stat -c %u "${SHARE_DIR}")" != "${owns_neither_location_uid}" ]
}

member_of_uv() {
  member_of_uv_groups="$(id -Gn)"
  case " ${member_of_uv_groups} " in
    *" uv "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Whether the interpreter link of the environment $1 resolves below the volume's python directory.
interpreter_on_volume() {
  interpreter_on_volume_target="$(readlink -f "$1/bin/python")"
  case "${interpreter_on_volume_target}" in
    "${VOLUME_DIR}"/python/*) return 0 ;;
    *) return 1 ;;
  esac
}

check "the tooling changed the remote user's UID" [ "$(id -u)" != "${BUILD_UID}" ]
check "the remote user no longer owns ${SHARE_DIR} or the new volume" owns_neither_location
check "the remote user is a member of the group uv" member_of_uv
check "the new volume belongs to the group uv and is writable by its members" \
  [ "$(stat -c '%G %a' "${VOLUME_DIR}")" = "uv 2775" ]

# Volume that fits: the repair script decides it with BusyBox find here.
warning="$(mktemp)"
check "the repair succeeds on the new volume" "${REPAIR}" 2>"${warning}"
check "no warning is printed on a volume that fits" test ! -s "${warning}"
rm "${warning}"

check "the remote user creates a virtual environment with a uv-managed interpreter" \
  uv venv --managed-python .changed-uid-venv
check "the interpreter is installed under ${VOLUME_DIR}" interpreter_on_volume .changed-uid-venv
check "the remote user reinstalls a build-time tool" uv tool install --reinstall pycowsay
check "the remote user removes a build-time tool" uv tool uninstall pycowsay
check "the remote user adds a tool" uv tool install cowsay
check "the added tool runs by name" cowsay -t hello

reportResults
