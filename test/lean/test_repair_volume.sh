#!/usr/bin/env bash
# Scenario "test_repair_volume": the creation script on the base image as vscode, who has passwordless sudo, with a
# build-time toolchain ("Volume filled under another UID", "Links into the image", "No passwordless sudo", "Volume that
# fits", the files left by root, and the special bits the repair clears).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly INITIALIZE="/usr/local/share/lean-feature/initialize"
readonly VOLUME_DIR="/var/lib/lean"
readonly IMAGE_TOOLCHAIN="/usr/local/share/lean/toolchains/leanprover--lean4---v4.35.0"
# A UID and GID that no account of the image has: the user that filled the volume before.
readonly FOREIGN_ID=23457
readonly EXTERNAL_FILE="/tmp/lean-repair-external-file"
readonly EXTERNAL_DIR="/tmp/lean-repair-external-dir"

work_dir=""

cleanup() {
  if [[ -n "${work_dir}" ]]; then rm -rf "${work_dir}"; fi
}

# Prints every entry of the volume with its owner, group, and mode, sorted; through sudo, which reads a volume of any
# owner.
volume_state() {
  sudo find "${VOLUME_DIR}" -printf '%P %U %G %m\n' | sort
}

volume_modes() {
  sudo find "${VOLUME_DIR}" -printf '%P %m\n' | sort
}

# Prints the owner, group, and mode of the link targets outside the volume and of the image's toolchain.
external_state() {
  stat -c '%u %g %a' "${EXTERNAL_FILE}" "${EXTERNAL_DIR}" "${EXTERNAL_DIR}/file" "${IMAGE_TOOLCHAIN}" \
    "${IMAGE_TOOLCHAIN}/bin/lean"
}

# Runs the creation script with the sudo stub first on PATH and keeps its warning; the arguments are NAME=value
# settings for the stub.
initialize_with_stub() {
  env PATH="${work_dir}/stubs:${PATH}" "$@" "${INITIALIZE}" 2>"${work_dir}/warning"
}

# Whether the kept warning starts with the script's prefix and the volume, and names the reason $1.
warning_names() {
  grep -q '^lean: warning: /var/lib/lean:' "${work_dir}/warning" && grep -q "$1" "${work_dir}/warning"
}

user_owns_everything_with_group_lean() {
  local not_owned not_in_group
  not_owned="$(find "${VOLUME_DIR}" -mindepth 1 ! -uid "$(id -u)" -print -quit)"
  not_in_group="$(find "${VOLUME_DIR}" -mindepth 1 ! -group lean -print -quit)"
  [[ -z "${not_owned}" && -z "${not_in_group}" ]]
}

toolchain_runs() {
  local output
  output="$(lean +leanprover/lean4:v4.35.0 --version)"
  [[ "${output}" == "Lean (version 4.35.0,"* ]]
}

# Fixtures get ordinary modes, whatever the remote user's umask is.
umask 022
trap cleanup EXIT
work_dir="$(mktemp -d)"

check "the remote user is not root" [ "$(id -u)" != 0 ]
check "the build-time toolchain is linked into the volume" \
  test -L "${VOLUME_DIR}/elan/toolchains/leanprover--lean4---v4.35.0"

# Volume filled under another UID. Setup: cache files and links to targets outside the volume, then everything in the
# volume given to another UID.
printf 'cached\n' >"${VOLUME_DIR}/cache/mathlib/fixture.ltar"
sudo mkdir -p "${EXTERNAL_DIR}"
sudo touch "${EXTERNAL_FILE}" "${EXTERNAL_DIR}/file"
ln -s "${EXTERNAL_FILE}" "${VOLUME_DIR}/cache/external-file"
ln -s "${EXTERNAL_DIR}" "${VOLUME_DIR}/cache/external-dir"
external_before="$(external_state)"
sudo chown -hR "${FOREIGN_ID}:${FOREIGN_ID}" "${VOLUME_DIR}"
modes_before="$(volume_modes)"
foreign_state="$(volume_state)"

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

check "the creation continues without passwordless sudo" initialize_with_stub SUDO_MODE=denied
check "a warning names ${VOLUME_DIR} and the reason, no passwordless sudo" warning_names 'passwordless sudo'
check "the volume keeps its owners without passwordless sudo" [ "$(volume_state)" == "${foreign_state}" ]

check "the creation continues when the change of owner fails" initialize_with_stub SUDO_MODE=failed
check "a warning names ${VOLUME_DIR} and the reason the change of owner failed" warning_names 'simulated chown failure'
check "the volume keeps its owners after the failed change of owner" [ "$(volume_state)" == "${foreign_state}" ]

# Volume filled under another UID and Links into the image: the repair with the image's passwordless sudo.
check "the creation continues on a volume that another UID filled, with passwordless sudo" "${INITIALIZE}"
check "the remote user owns everything in the volume and all of it has the group lean" \
  user_owns_everything_with_group_lean
check "the repair preserves permission bits" [ "$(volume_modes)" == "${modes_before}" ]
check "the repair changes nothing outside ${VOLUME_DIR}, the image's toolchain included" \
  [ "$(external_state)" == "${external_before}" ]
check "the build-time toolchain runs without a download" toolchain_runs
check "the cache files are kept" [ "$(cat "${VOLUME_DIR}/cache/mathlib/fixture.ltar")" == "cached" ]

# Executable special bits during repair. Setup: a foreign executable with mode 6755 in a foreign directory with mode
# 2775.
special_dir="${VOLUME_DIR}/cache/special-modes"
special_file="${special_dir}/executable"
mkdir "${special_dir}"
printf '%s\n' 'mode fixture' >"${special_file}"
sudo chown -hR "${FOREIGN_ID}:${FOREIGN_ID}" "${special_dir}"
sudo chmod 2775 "${special_dir}"
sudo chmod 6755 "${special_file}"

check "the foreign executable has mode 6755 before the repair" [ "$(stat -c %a "${special_file}")" == 6755 ]
check "the creation continues on a volume with a foreign setuid and setgid executable" "${INITIALIZE}"
check "the ownership change clears the setuid and setgid bits, which the repair does not restore" \
  [ "$(stat -c %a "${special_file}")" == 755 ]
check "the directory keeps its mode" [ "$(stat -c %a "${special_dir}")" == 2775 ]
check "the file's contents are preserved" [ "$(cat "${special_file}")" == 'mode fixture' ]

# Volume that fits. Setup: a sudo stub that records that it ran.
cat >"${work_dir}/stubs/sudo" <<'STUB'
#!/bin/sh
: >"${SUDO_RECORD}"
exit 1
STUB
fitting_state="$(volume_state)"

check "the creation continues on a volume that fits" initialize_with_stub SUDO_RECORD="${work_dir}/called"
check "sudo is not run on a volume that fits" test ! -e "${work_dir}/called"
check "no warning is printed on a volume that fits" test ! -s "${work_dir}/warning"
check "nothing in the volume changes" [ "$(volume_state)" == "${fitting_state}" ]

# Files left by root. Setup: a file that root wrote among the remote user's own.
sudo mkdir -p "${VOLUME_DIR}/cache/lake/root"
sudo touch "${VOLUME_DIR}/cache/lake/root/file"

check "the creation continues on a volume with a file that root left" "${INITIALIZE}"
check "the remote user owns the file that root left" \
  [ "$(stat -c %u "${VOLUME_DIR}/cache/lake/root/file")" == "$(id -u)" ]

reportResults
