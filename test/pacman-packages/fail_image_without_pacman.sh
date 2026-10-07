#!/usr/bin/env bash
# Scenario fail_image_without_pacman (scenarios.json): the scenario's Dockerfile builds an Alpine image, which has no
# pacman and whose /bin/sh is busybox, and the container has no network. Spec scenarios "Image without pacman fails
# clearly", and on an image without pacman "Omitted packages", "Empty list is a no-op", "URL or path is refused",
# "Option-like entry is refused", and "Shell metacharacters and inner whitespace are refused".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly EMPTY_LISTS=("" $' , ,\t, ' ",")

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.pkg.tar.zst" "./bc.pkg.tar.zst" "${ARCHIVE}/b/bc/bc.pkg.tar.zst" "file:///tmp/bc.pkg.tar.zst" "extra/bc"
  # Option-like entry
  "--nodeps" "-dd" "--assume-installed=glibc" "-"
  # Shell metacharacters and inner whitespace; the last entry ends in a non-ASCII letter, c with acute, as its UTF-8
  # bytes
  "x;touch /tmp/pwned" "\$(touch /tmp/pwned)" "\`touch /tmp/pwned\`" "bc|touch /tmp/pwned" "bc&&touch /tmp/pwned"
  "b*" "b?" "bc~1" "bc tree" $'bc\ttree' $'b\xc4\x87'
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

sh_is_busybox() {
  [[ "$(readlink -f /bin/sh)" == *busybox* ]]
}

# The entry $1 is refused with status 1 and named, and no command in it ran. The valid entry tree runs beside it.
refuses_entry() {
  run_install PACKAGES="tree,$1"
  exited_with 1 && refused "$1" && test ! -e /tmp/pwned
}

state_before="$(image_state)"

run_install
check "without packages the feature exits with status 0" exited_with 0
check "the run without packages changed nothing in the image" image_state_is "${state_before}"
for list in "${EMPTY_LISTS[@]}"; do
  run_install PACKAGES="${list}"
  check "with packages='${list}' the feature exits with status 0" exited_with 0
done
check "the runs with an empty list changed nothing in the image" image_state_is "${state_before}"

run_install PACKAGES=bc
check "with packages=bc the feature exits with status 1" exited_with 1
# "pacman" alone is also in the "pacman-packages:" prefix of every message.
check "the message says that pacman was not found" printed "pacman was not found"
check "the message names Arch Linux" printed "Arch Linux"
check "the failed run changed nothing in the image" image_state_is "${state_before}"

check "premise: /bin/sh is busybox" sh_is_busybox
for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 and no command in it runs" refuses_entry "${entry}"
done

reportResults
