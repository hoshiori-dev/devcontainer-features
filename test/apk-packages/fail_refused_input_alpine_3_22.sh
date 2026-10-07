#!/bin/sh
# Scenario fail_refused_input_alpine_3_22 (scenarios.json): the feature is installed with an empty list, the container
# has no network, and this script then runs install.sh with input that validation refuses. Spec scenarios "URL or path
# is refused", "Option-like entry is refused", "Conflict marker is refused", "Shell metacharacters and inner whitespace
# are refused", "Invalid control fails before any change", "Empty list ignores installation controls", and "Timeout
# boundaries are validated".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

TAB="$(printf '\t')"
readonly TAB
# U+0435, the Cyrillic letter that looks like the Latin e.
CYRILLIC_IE="$(printf '\320\265')"
readonly CYRILLIC_IE

# A PATH on which apk is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"

# The entry $1 is refused with status 1 and named, and nothing changed: apk's world, its installed database, and the
# caches are as before, and no command in the entry ran. The valid entry file runs beside it, so a gap in the
# validation would reach apk. The message naming the entry, not the exit status, shows that validation came before the
# index refresh: without a network a refresh also exits 1, with another message.
refuses_entry() {
  run_install PACKAGES="file,$1"
  exited_with 1 && printed "refusing the entry '$1'" && apk_state_is "${state_before}" && nothing_ran
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2.
refuses_control() {
  run_install PATH="${STUB_PATH}" PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}"
}

# Neither the package manager nor shell text in a value ran.
nothing_ran() {
  if [ -e /tmp/manager-called ] || [ -e /tmp/pwned ]; then
    echo "apk was called, or a command in a value ran" >&2
    return 1
  fi
}

state_before="$(apk_state)"
configuration_before="$(apk_configuration)"

# URL or path
for entry in "/tmp/tree.apk" "./tree.apk" "tree.apk/" "https://example.com/tree.apk" "community/tree"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done
# Option-like entry
for entry in "--allow-untrusted" "-u" "--force-missing-repositories" "-X"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done
# Conflict marker
for entry in '!busybox' '!tree'; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done
check "busybox, which a conflict marker named, is still installed" installed busybox
# Shell metacharacters and inner whitespace, and letters outside ASCII
for entry in 'x;touch /tmp/pwned' "\$(touch /tmp/pwned)" "\`touch /tmp/pwned\`" 'tree|touch /tmp/pwned' \
  'tree&&touch /tmp/pwned' "tree\$HOME" 't*' 't?' 'tree file' "tree${TAB}file" 'trée' "tr${CYRILLIC_IE}e"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/apk
chmod +x /tmp/stub/apk

# Each control is "<option> <environment assignment>" with a value the option does not accept.
for control in \
  "cleanup CLEANUP=invalid" "cleanup CLEANUP=" \
  "refreshPolicy REFRESHPOLICY=invalid" "refreshPolicy REFRESHPOLICY=" \
  "upgradePackages UPGRADEPACKAGES=yes" "upgradePackages UPGRADEPACKAGES=" \
  "networkTimeout NETWORKTIMEOUT=0" "networkTimeout NETWORKTIMEOUT=3601" "networkTimeout NETWORKTIMEOUT=01" \
  "networkTimeout NETWORKTIMEOUT=-1" "networkTimeout NETWORKTIMEOUT=+1" "networkTimeout NETWORKTIMEOUT=1 " \
  "networkTimeout NETWORKTIMEOUT=1.5" "networkTimeout NETWORKTIMEOUT=１２" \
  "networkTimeout NETWORKTIMEOUT=\$(touch /tmp/pwned)" "networkTimeout NETWORKTIMEOUT=999999999999999999999999"; do
  check "'${control#* }' fails with status 1 and names ${control%% *}, with an empty list" \
    refuses_control "${control}" ""
  check "'${control#* }' fails with status 1 and names ${control%% *}, with the list tree" \
    refuses_control "${control}" "tree"
done

for cleanup in all packages none; do
  run_install PATH="${STUB_PATH}" PACKAGES=" ,${TAB}, " CLEANUP="${cleanup}"
  check "a list of commas and whitespace succeeds with cleanup=${cleanup}" exited_with 0
done
for timeout in "" 1 3600; do
  run_install PATH="${STUB_PATH}" PACKAGES="" NETWORKTIMEOUT="${timeout}"
  check "an empty list succeeds with networkTimeout='${timeout}'" exited_with 0
done

check "no run called apk or ran shell text from a value" nothing_ran
check "no run changed apk's world, its installed database, or a cache" apk_state_is "${state_before}"
check "no run changed the apk configuration" apk_configuration_is "${configuration_before}"

reportResults
