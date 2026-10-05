#!/usr/bin/env bash
# Scenario "repair_volume": the volume-repair script on the Ubuntu base image as vscode, who has passwordless sudo
# ("Volume filled under another UID", "Files left by root", "Executable special bits during repair", "No
# passwordless sudo", "Volume that fits").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly REPAIR="/usr/local/share/uv-feature/repair-volume"
readonly VOLUME_DIR="/var/lib/uv"
# A UID and GID that no account of the image has: the user that filled the volume before.
readonly FOREIGN_ID=23457
readonly EXTERNAL_FILE="/tmp/uv-repair-external-file"
readonly EXTERNAL_DIR="/tmp/uv-repair-external-dir"

work_dir=""

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm -rf "${work_dir}"; fi
}

# Prints every entry of the volume with its mode, sorted; through sudo, which reads a volume of any owner.
volume_modes() {
  sudo find "${VOLUME_DIR}" -printf '%P %m\n' | sort
}

# Prints every entry of the volume with its owner, group, and mode, sorted; through sudo, as volume_modes.
volume_state() {
  sudo find "${VOLUME_DIR}" -printf '%P %U %G %m\n' | sort
}

# Prints the owner, group, and mode of the link targets outside the volume.
external_state() {
  stat -c '%u %g %a' "${EXTERNAL_FILE}" "${EXTERNAL_DIR}" "${EXTERNAL_DIR}/file"
}

# Whether uv fails on the volume because it cannot initialize its cache there.
uv_fails_on_the_volume() {
  if uv venv --managed-python "${work_dir}/broken" >"${work_dir}/broken.log" 2>&1; then return 1; fi
  grep -q 'Failed to initialize cache' "${work_dir}/broken.log"
}

# Runs the repair script with the sudo stub first on PATH and keeps its warning; the arguments are NAME=value
# settings for the stub.
repair_with_stub() {
  env PATH="${work_dir}/stubs:${PATH}" "$@" "${REPAIR}" 2>"${work_dir}/warning"
}

# Whether the kept warning starts with the script's prefix and the volume, names the reason $1, and points to the
# feature's NOTES.md.
warning_names() {
  grep -q '^uv: warning: /var/lib/uv:' "${work_dir}/warning" \
    && grep -q "$1" "${work_dir}/warning" \
    && grep -q 'NOTES.md' "${work_dir}/warning"
}

user_owns_everything_with_group_uv() {
  local not_owned not_in_group
  not_owned="$(find "${VOLUME_DIR}" ! -uid "$(id -u)" -print -quit)"
  not_in_group="$(find "${VOLUME_DIR}" ! -group uv -print -quit)"
  [[ -z "${not_owned}" && -z "${not_in_group}" ]]
}

# Fixtures get ordinary modes, whatever the remote user's umask is.
umask 022
trap cleanup EXIT
work_dir="$(mktemp -d)"

check "the remote user is not root" [ "$(id -u)" != 0 ]

# Volume filled under another UID. Setup: an interpreter and a cached package on the volume, links in it to targets
# outside it, then everything in it given to another UID.
uv venv --managed-python "${work_dir}/first"
uv pip install --python "${work_dir}/first/bin/python" pycowsay
sudo mkdir -p "${EXTERNAL_DIR}"
sudo touch "${EXTERNAL_FILE}" "${EXTERNAL_DIR}/file"
ln -s "${EXTERNAL_FILE}" "${VOLUME_DIR}/cache/external-file"
ln -s "${EXTERNAL_DIR}" "${VOLUME_DIR}/cache/external-dir"
external_before="$(external_state)"
sudo chown -hR "${FOREIGN_ID}:${FOREIGN_ID}" "${VOLUME_DIR}"
modes_before="$(volume_modes)"
foreign_state="$(volume_state)"

check "uv fails on a volume that another UID filled" uv_fails_on_the_volume

# No passwordless sudo. Setup: a sudo stub that accepts only `sudo -n`, refuses `sudo -n true` when SUDO_MODE is
# denied, and fails every other command as a failing chown would.
mkdir "${work_dir}/stubs"
cat >"${work_dir}/stubs/sudo" <<'STUB'
#!/bin/sh
[ "$1" = "-n" ] || exit 99
if [ "$2" = "true" ]; then
  if [ "${SUDO_MODE}" != "denied" ]; then exit 0; fi
  echo 'password required' >&2
  exit 1
fi
echo 'simulated chown failure' >&2
exit 1
STUB
chmod +x "${work_dir}/stubs/sudo"

check "the creation continues without passwordless sudo" repair_with_stub SUDO_MODE=denied
check "a warning names ${VOLUME_DIR} and the reason, no passwordless sudo" warning_names 'passwordless sudo'
check "the volume keeps its owner, group, and modes without passwordless sudo" \
  [ "$(volume_state)" = "${foreign_state}" ]

check "the creation continues when the change of owner fails" repair_with_stub SUDO_MODE=failed
check "a warning names ${VOLUME_DIR} and the reason the change of owner failed" \
  warning_names 'simulated chown failure'
check "the volume keeps its owner, group, and modes after the failed change of owner" \
  [ "$(volume_state)" = "${foreign_state}" ]

# Volume filled under another UID: the repair with the image's passwordless sudo.
check "the creation continues and repairs the volume with passwordless sudo" "${REPAIR}"
check "the remote user owns everything in the volume and all of it has the group uv" \
  user_owns_everything_with_group_uv
check "the repair preserves ordinary permission bits" [ "$(volume_modes)" = "${modes_before}" ]
check "the repair changes nothing outside ${VOLUME_DIR}" [ "$(external_state)" = "${external_before}" ]
check "the interpreter the volume already held creates an environment offline" \
  uv venv --offline --managed-python "${work_dir}/offline"
check "the remote user installs a package from the cache the volume already held without downloading it" \
  uv pip install --offline --python "${work_dir}/offline/bin/python" pycowsay
check "the remote user installs a further uv-managed interpreter" uv python install 3.13

# Executable special bits during repair. Setup: a foreign directory with mode 2775 that holds a foreign executable
# with mode 6755.
special_dir="${VOLUME_DIR}/cache/special-modes"
special_file="${special_dir}/executable"
mkdir "${special_dir}"
printf '%s\n' 'mode fixture' >"${special_file}"
sudo chown -hR "${FOREIGN_ID}:${FOREIGN_ID}" "${special_dir}"
# The special bits are set after the foreign owner, so the repair really encounters them.
sudo chmod 2775 "${special_dir}"
sudo chmod 6755 "${special_file}"

check "the foreign executable has mode 6755 before the repair" [ "$(stat -c %a "${special_file}")" = 6755 ]
check "the creation continues and repairs the special-bit fixture" "${REPAIR}"
check "the ownership change clears the executable's setuid and setgid bits to mode 0755" \
  [ "$(stat -c %a "${special_file}")" = 755 ]
check "the directory stays 2775" [ "$(stat -c %a "${special_dir}")" = 2775 ]
check "the file's contents are preserved" [ "$(cat "${special_file}")" = 'mode fixture' ]
check "the executable belongs to the remote user and the group uv" \
  [ "$(stat -c '%u %G' "${special_file}")" = "$(id -u) uv" ]

# Volume that fits. Setup: a sudo stub that records that it ran, and special bits back on the executable, which a
# volume that fits may hold.
cat >"${work_dir}/stubs/sudo" <<'STUB'
#!/bin/sh
: >"${SUDO_RECORD}"
exit 1
STUB
chmod 6755 "${special_file}"
fitting_state="$(volume_state)"

check "the executable has mode 6755 on the volume that fits" [ "$(stat -c %a "${special_file}")" = 6755 ]
check "the creation continues on a volume that fits" repair_with_stub SUDO_RECORD="${work_dir}/called"
check "sudo is not run on a volume that fits" test ! -e "${work_dir}/called"
check "no warning is printed on a volume that fits" test ! -s "${work_dir}/warning"
check "nothing in the volume changes" [ "$(volume_state)" = "${fitting_state}" ]

# Files left by root. Setup: a file that root wrote among the remote user's own.
sudo mkdir -p "${VOLUME_DIR}/cache/deep/root"
sudo touch "${VOLUME_DIR}/cache/deep/root/file"

check "the creation continues and repairs the files that root left" "${REPAIR}"
check "the remote user owns the file that root left" \
  [ "$(stat -c %u "${VOLUME_DIR}/cache/deep/root/file")" = "$(id -u)" ]

reportResults
