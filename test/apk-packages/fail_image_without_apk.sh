#!/bin/sh
# Scenario fail_image_without_apk (scenarios.json): the scenario's Dockerfile builds a Debian image, which has no apk,
# and the container has no network. Spec scenarios "Image without apk fails clearly", "Omitted packages" and "Empty
# list is a no-op" on an image without apk, and "URL or path is refused" there: validation comes before the apk check.
# POSIX sh with the stand-in in checks.sh, as every script of this feature; installer.sh's assertions about apk are
# not used here.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

TAB="$(printf '\t')"
readonly TAB

# Prints a digest of the image: the file names under the system directories, the content of /etc, and dpkg's database.
image_state() {
  {
    find /bin /etc /lib /opt /root /sbin /tmp /usr /var -xdev 2>/dev/null | sort
    find /etc -type f -exec sha256sum {} + | sort
    sha256sum /var/lib/dpkg/status
  } | sha256sum
}

image_state_is() {
  if [ "$(image_state)" != "$1" ]; then
    echo "the image changed" >&2
    return 1
  fi
}

# The last run did not reach the check for apk.
did_not_look_for_apk() {
  if output_matches 'was not found'; then
    echo "the apk check ran before validation" >&2
    return 1
  fi
}

state_before="$(image_state)"

run_install
check "without packages the feature exits with status 0" exited_with 0
check "the run without packages changed nothing in the image" image_state_is "${state_before}"

for list in "" " , ,${TAB}, " ","; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
check "the runs with an empty list changed nothing in the image" image_state_is "${state_before}"

run_install PACKAGES="file,tree>=1"
check "with packages='file,tree>=1' the feature exits with status 1" exited_with 1
check "the message names apk" printed "apk"
check "the message names Alpine Linux" printed "Alpine Linux"
check "the failed run changed nothing in the image" image_state_is "${state_before}"

run_install PACKAGES="file,/tmp/tree.apk"
check "with packages='file,/tmp/tree.apk' the feature exits with status 1" exited_with 1
check "the message refuses the entry /tmp/tree.apk" printed "refusing the entry '/tmp/tree.apk'"
check "the refusal comes before the check for apk" did_not_look_for_apk
check "the refused run changed nothing in the image" image_state_is "${state_before}"

reportResults
