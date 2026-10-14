#!/usr/bin/env bash
# Scenario fail_image_without_apt_get (scenarios.json): the scenario's Dockerfile builds an Alpine image, which has no
# apt-get, and the container has no network. Spec scenarios "Image without apt-get fails clearly", and "Omitted
# packages", "Empty list is a no-op", "Empty list ignores installation controls", and "Invalid control fails before any
# change" on an image without apt-get.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly EMPTY_LISTS=("" $' , ,\t, ' ",")
# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=(
  "installSuggests INSTALLSUGGESTS=yes" "conffilePolicy CONFFILEPOLICY=inherit" "downloadRetries DOWNLOADRETRIES=11"
  "downloadRetries DOWNLOADRETRIES=99999999999999999999" "lockTimeout LOCKTIMEOUT=0"
  "lockTimeout LOCKTIMEOUT=99999999999999999999" "targetRelease TARGETRELEASE=a=noble" "targetRelease TARGETRELEASE=NOW"
)

# Prints a digest of the image: the file names under the system directories, the content of /etc, and apk's database.
image_state() {
  {
    find /bin /etc /lib /opt /root /sbin /usr /var -xdev 2>/dev/null | sort
    find /etc -type f -exec sha256sum {} + | sort
    cat /lib/apk/db/installed
  } | sha256sum
}

image_state_is() {
  if [[ "$(image_state)" != "$1" ]]; then
    echo "the image changed" >&2
    return 1
  fi
}

state_before="$(image_state)"

run_install
check "without packages the feature exits with status 0" exited_with 0
for list in "${EMPTY_LISTS[@]}"; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
run_install TARGETRELEASE=bookworm INSTALLSUGGESTS=true CONFFILEPOLICY=replace DOWNLOADRETRIES=10 LOCKTIMEOUT=3600
check "without packages and with every new control set the feature exits with status 0" exited_with 0
for control in "${INVALID_CONTROLS[@]}"; do
  run_install "${control#* }"
  check "without packages '${control#* }' fails with status 1" exited_with 1
  check "the message names ${control%% *}" printed "${control%% *}"
done
check "the runs without a package changed nothing in the image" image_state_is "${state_before}"

run_install PACKAGES=bc
check "with packages=bc the feature exits with status 1" exited_with 1
check "the message names apt-get" printed "apt-get"
check "the message names Debian" printed "Debian"
check "the message names Ubuntu" printed "Ubuntu"
check "the failed run changed nothing in the image" image_state_is "${state_before}"

reportResults
