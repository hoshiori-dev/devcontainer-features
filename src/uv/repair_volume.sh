#!/bin/sh
# Makes the remote user the owner of the uv volume at /var/lib/uv, through passwordless sudo, when another UID wrote
# it; changes nothing on a volume that fits, for root, or outside the volume. install.sh installs it as
# /usr/local/share/uv-feature/repair-volume, and onCreateCommand runs it as the remote user once per container, before
# the user's creation commands. It takes no options.
# POSIX sh, because Alpine ships no bash.
#
# A failed repair must not stop the creation of the dev container (openspec/specs/uv/spec.md, "Repair a volume that
# no longer fits the remote user"). So, unlike the shell style guide's skeleton, this script does not enable set -e,
# every path through main returns 0, and it defines warn instead of an exiting fail; it defines no log, because it
# prints nothing when nothing is wrong.

readonly VOLUME_DIR="/var/lib/uv"

# Prints a warning about the volume to standard error; $1 is the reason.
warn() {
  printf '%s\n' "uv: warning: ${VOLUME_DIR}: $1; see the uv feature's NOTES.md for manual repair" >&2
}

# Whether the volume fits the user with the UID $1: that user can create files in it and owns everything below it.
volume_fits() {
  if [ ! -w "${VOLUME_DIR}" ] || [ ! -x "${VOLUME_DIR}" ]; then return 1; fi
  if command -v find >/dev/null 2>&1; then
    if ! volume_fits_foreign="$(find "${VOLUME_DIR}" -mindepth 1 ! -user "$1" -print -quit 2>&1)"; then return 1; fi
    if [ -n "${volume_fits_foreign}" ]; then return 1; fi
    return 0
  fi
  # An image without find, such as opensuse/leap:16.0, lists the volume with ls instead. GNU ls there sees hidden
  # entries, escapes newlines in names, and does not follow symbolic links; the numeric owner is field three of each
  # entry's long format.
  if ! volume_fits_listing="$(LC_ALL=C ls -lnARb -- "${VOLUME_DIR}" 2>&1)"; then return 1; fi
  awk -v uid="$1" '
    $1 ~ /^[-bcdlps]/ && $3 != uid {foreign=1}
    END {exit foreign ? 1 : 0}
  ' <<EOF
${volume_fits_listing}
EOF
}

main() {
  if ! main_uid="$(id -u)"; then
    warn "cannot determine the remote user's UID"
    return 0
  fi
  if [ "${main_uid}" = 0 ]; then return 0; fi
  if volume_fits "${main_uid}"; then return 0; fi

  if ! command -v sudo >/dev/null 2>&1; then
    warn "the volume does not fit this user and sudo is unavailable"
    return 0
  fi
  if ! main_reason="$(sudo -n true 2>&1)"; then
    warn "passwordless sudo is unavailable: ${main_reason}"
    return 0
  fi
  main_group="$(awk -F: '$1 == "uv" {print $3}' /etc/group)"
  main_owner="${main_uid}"
  if [ -n "${main_group}" ]; then main_owner="${main_uid}:${main_group}"; fi
  # --no-dereference keeps even a symbolic link named on the command line from changing an external target, and a
  # recursive chown never follows links inside the volume. It may clear setuid and setgid on executable files; it
  # changes no path outside the volume and runs no chmod.
  if ! main_reason="$(sudo -n chown --no-dereference --recursive "${main_owner}" "${VOLUME_DIR}" 2>&1)"; then
    warn "cannot change the volume's owner: ${main_reason}"
  fi
  return 0
}

main "$@"
