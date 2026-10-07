#!/usr/bin/env bash
# Scenario fail_refused_input (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh with input that validation refuses. Spec scenarios "URL or path is refused", "Option-like entry is
# refused", "Shell metacharacters and inner whitespace are refused", "Invalid control fails before any change", and
# "Empty list ignores installation controls".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.pkg.tar.zst" "./bc.pkg.tar.zst" "${ARCHIVE}/b/bc/bc.pkg.tar.zst" "file:///tmp/bc.pkg.tar.zst" "extra/bc"
  # Option-like entry
  "--nodeps" "-dd" "--assume-installed=glibc" "-"
  # Shell metacharacters and inner whitespace; the last entry ends in a non-ASCII letter, c with acute, as its UTF-8
  # bytes
  "x;touch /tmp/pwned" "\$(touch /tmp/pwned)" "\`touch /tmp/pwned\`" "bc|touch /tmp/pwned" "bc&&touch /tmp/pwned"
  "b*" "b?" "bc~1" "bc tree" $'bc\ttree' $'bć'
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=("cleanup CLEANUP=invalid" "cleanup CLEANUP=")

# A PATH on which pacman is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"

# The entry $1 is refused with status 1 and named, and nothing changed: no sync database was downloaded, no package
# changed, and no command in the entry ran. The valid entry tree runs beside it, so a gap in the validation would
# install something.
refuses_entry() {
  run_install PACKAGES="tree,$1"
  exited_with 1 && refused "$1" && no_sync_databases && local_database_is "${database_before}" && nothing_ran
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2.
refuses_control() {
  run_install PATH="${STUB_PATH}" PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}"
}

# Neither the package manager nor shell text in a value ran.
nothing_ran() {
  if [[ -e /tmp/manager-called || -e /tmp/pwned ]]; then
    echo "pacman was called, or a command in a value ran" >&2
    return 1
  fi
}

database_before="$(local_database)"
configuration_before="$(repository_configuration)"

for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/pacman
chmod +x /tmp/stub/pacman

for control in "${INVALID_CONTROLS[@]}"; do
  check "'${control#* }' fails with status 1 and names ${control%% *}, with an empty list" \
    refuses_control "${control}" ""
  check "'${control#* }' fails with status 1 and names ${control%% *}, with the list tree" \
    refuses_control "${control}" "tree"
done

for cleanup in all packages none; do
  run_install PATH="${STUB_PATH}" PACKAGES=$' ,\t, ' CLEANUP="${cleanup}"
  check "a list of commas and whitespace succeeds with cleanup=${cleanup}" exited_with 0
done

check "no run called pacman or ran shell text from a value" nothing_ran
check "no run changed an installed package" local_database_is "${database_before}"
check "no run changed the repository configuration" repository_configuration_is "${configuration_before}"

reportResults
