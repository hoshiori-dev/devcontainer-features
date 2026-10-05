#!/bin/sh
# Install-twice test ("Different options"): uv is installed first with non-default options, the second proposal of
# each option (version 0.12.16, toolsToInstall pycowsay), then with the defaults (version latest, no tools). POSIX sh,
# because alpine:3.24 ships no bash.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

readonly VOLUME_DIR="/var/lib/uv"
readonly SHARE_DIR="/usr/local/share/uv"

is_mount() {
  grep -q "^[^ ]* [^ ]* [^ ]* [^ ]* $1 " /proc/self/mountinfo
}

is_empty_dir() {
  [ -d "$1" ] && [ -z "$(ls -A "$1")" ]
}

# Whether `$1 --version` names the release $2 as its second word: "uv 0.12.16 (x86_64-unknown-linux-gnu)".
reports_release() {
  reports_release_line="$("$1" --version)"
  reports_release_rest="${reports_release_line#* }"
  [ "${reports_release_rest%% *}" = "$2" ]
}

# Whether the file $1 exists and has none of the permission bits of the octal mode $2.
lacks_mode_bits() {
  lacks_mode_bits_found="$(find "$1" -perm "-$2" -print)"
  [ -e "$1" ] && [ -z "${lacks_mode_bits_found}" ]
}

one_group_uv_lists_the_user_once() {
  one_group_uv_lists_the_user_once_user="$(id -un)"
  awk -F: -v user="${one_group_uv_lists_the_user_once_user}" '
    $1 == "uv" { groups++; n = split($4, members, ","); for (i = 1; i <= n; i++) if (members[i] == user) listed++ }
    END { exit !(groups == 1 && listed == 1) }
  ' /etc/group
}

check "${VOLUME_DIR} is a mount of the volume" is_mount "${VOLUME_DIR}"
check "the volume holds no files after two installs" is_empty_dir "${VOLUME_DIR}"

# The second install's version is `latest`: the release it names when the test runs cannot be a literal; a release
# published between the image build and the test fails once.
latest_url="$(curl --proto '=https' --tlsv1.2 -fsS -o /dev/null -w '%{redirect_url}' \
  https://github.com/astral-sh/uv/releases/latest)"
second_release="${latest_url##*/}"
printf '%s\n' "Expecting uv ${second_release}"
check "uv --version reports the second install's release" reports_release uv "${second_release}"
check "uvx --version reports the second install's release" reports_release uvx "${second_release}"

# Nothing writable by every user: uv's lock files, which the first install's tool created.
for lock in "${SHARE_DIR}/tools/.lock" "${SHARE_DIR}/python/.lock"; do
  check "${lock} is not writable by every user" lacks_mode_bits "${lock}" 0002
  if [ "$(id -u)" = 0 ]; then
    check "${lock} is writable by root only" lacks_mode_bits "${lock}" 0020
  fi
done

# Group after a second install.
if [ "$(id -u)" != 0 ]; then
  check "the image has one group uv that lists the remote user once" one_group_uv_lists_the_user_once
  check "the tool of the first install belongs to the group uv and is writable by its members" \
    [ "$(stat -c '%G %a' "${SHARE_DIR}/tools/pycowsay")" = "uv 2775" ]
fi

# Different options: the first install's tool remains installed after a second install without tools.
check "the tool of the first install runs by name" pycowsay hello

reportResults
