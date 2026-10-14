#!/usr/bin/env bash
# Scenario fail_refused_input_debian (scenarios.json): the feature is installed with an empty list, and this script
# then runs install.sh with input that validation refuses. Spec scenarios "URL or path is refused", "Option-like entry
# is refused", "Removal marker is refused", "Upper-case package name is refused", "Shell metacharacters and inner
# whitespace are refused", "Invalid control fails before any change", "Empty list ignores installation controls",
# "Timeout boundaries are validated", "Retry boundaries are validated", "Lock timeout boundaries are validated", "Target
# release syntax is validated", and "Undeclared policy or boolean value is refused".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.deb" "./bc.deb" "http://deb.debian.org/debian/bc.deb" "bc/stable"
  # Option-like entry
  "--allow-unauthenticated" "-y" "-oAPT::Get::AllowUnauthenticated=true"
  # Removal marker
  "bc-" "apt-" "bc=1.0-"
  # Upper-case package name
  "Python3.11" "Bc"
  # Shell metacharacters and inner whitespace
  "x;touch /tmp/pwned" "\$(touch /tmp/pwned)" "\`touch /tmp/pwned\`" "bc|touch /tmp/pwned" "bc&&touch /tmp/pwned"
  "bc>/tmp/pwned" "b*" "b?" "bc file" $'bc\tfile'
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=(
  "cleanup CLEANUP=invalid" "cleanup CLEANUP="
  "refreshPolicy REFRESHPOLICY=invalid" "refreshPolicy REFRESHPOLICY="
  "installRecommends INSTALLRECOMMENDS=yes" "installRecommends INSTALLRECOMMENDS="
  "networkTimeout NETWORKTIMEOUT=0" "networkTimeout NETWORKTIMEOUT=3601" "networkTimeout NETWORKTIMEOUT=01"
  "networkTimeout NETWORKTIMEOUT=-1" "networkTimeout NETWORKTIMEOUT=+1" "networkTimeout NETWORKTIMEOUT=1 "
  "networkTimeout NETWORKTIMEOUT=1.5" "networkTimeout NETWORKTIMEOUT=１２"
  "networkTimeout NETWORKTIMEOUT=\$(touch /tmp/pwned)" "networkTimeout NETWORKTIMEOUT=999999999999999999999999"
  "installSuggests INSTALLSUGGESTS=yes" "installSuggests INSTALLSUGGESTS="
  "conffilePolicy CONFFILEPOLICY=" "conffilePolicy CONFFILEPOLICY=inherit" "conffilePolicy CONFFILEPOLICY=ask"
  "conffilePolicy CONFFILEPOLICY=--force-confnew" "conffilePolicy CONFFILEPOLICY=keep,replace"
  "downloadRetries DOWNLOADRETRIES=11" "downloadRetries DOWNLOADRETRIES=00" "downloadRetries DOWNLOADRETRIES=01"
  "downloadRetries DOWNLOADRETRIES=-1" "downloadRetries DOWNLOADRETRIES=+1" "downloadRetries DOWNLOADRETRIES=1.5"
  "downloadRetries DOWNLOADRETRIES=1 " "downloadRetries DOWNLOADRETRIES=3x" "downloadRetries DOWNLOADRETRIES=abc"
  "downloadRetries DOWNLOADRETRIES=99999999999999999999" "downloadRetries DOWNLOADRETRIES=\$(touch /tmp/pwned)"
  "lockTimeout LOCKTIMEOUT=0" "lockTimeout LOCKTIMEOUT=3601" "lockTimeout LOCKTIMEOUT=01" "lockTimeout LOCKTIMEOUT=-1"
  "lockTimeout LOCKTIMEOUT=+1" "lockTimeout LOCKTIMEOUT=1.5" "lockTimeout LOCKTIMEOUT=1 " "lockTimeout LOCKTIMEOUT=abc"
  "lockTimeout LOCKTIMEOUT=99999999999999999999" "lockTimeout LOCKTIMEOUT=\$(touch /tmp/pwned)"
  "targetRelease TARGETRELEASE=a=noble-updates" "targetRelease TARGETRELEASE=n=bookworm"
  "targetRelease TARGETRELEASE=bookworm/main" "targetRelease TARGETRELEASE=12*" "targetRelease TARGETRELEASE=bookwor?"
  "targetRelease TARGETRELEASE=[bn]ookworm" "targetRelease TARGETRELEASE=/^bookworm(|-security|-updates)\$/"
  "targetRelease TARGETRELEASE=bookworm,trixie" "targetRelease TARGETRELEASE=bookworm trixie"
  "targetRelease TARGETRELEASE=bookworm " $'targetRelease TARGETRELEASE=book\tworm'
  "targetRelease TARGETRELEASE=\$(touch /tmp/pwned)" "targetRelease TARGETRELEASE=bookworm;touch /tmp/pwned"
  "targetRelease TARGETRELEASE=-t" "targetRelease TARGETRELEASE=-bookworm" "targetRelease TARGETRELEASE=.bookworm"
  "targetRelease TARGETRELEASE=now" "targetRelease TARGETRELEASE=NOW" "targetRelease TARGETRELEASE=Now"
  # 65 characters, one more than the longest accepted name
  "targetRelease TARGETRELEASE=a123456789b123456789c123456789d123456789e123456789f123456789g1234"
)

# Each entry is an environment assignment with a value the option accepts; an empty value stands for the default of
# the three options that inherit.
readonly VALID_CONTROLS=(
  "INSTALLSUGGESTS=true" "INSTALLSUGGESTS=false" "CONFFILEPOLICY=keep" "CONFFILEPOLICY=replace"
  "DOWNLOADRETRIES=" "DOWNLOADRETRIES=0" "DOWNLOADRETRIES=10" "LOCKTIMEOUT=" "LOCKTIMEOUT=1" "LOCKTIMEOUT=3600"
  "TARGETRELEASE=" "TARGETRELEASE=noble-updates" "TARGETRELEASE=bookworm" "TARGETRELEASE=12.15" "TARGETRELEASE=snow"
  # 64 characters, the longest accepted name
  "TARGETRELEASE=a123456789b123456789c123456789d123456789e123456789f123456789g123"
)

# A PATH on which apt-get is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"

# The entry $1 is refused with status 1 and named, and nothing changed: no index was fetched, no package changed, and
# no command in the entry ran. The valid entry file runs beside it, so a gap in the validation would install something.
refuses_entry() {
  run_install PACKAGES="file,$1"
  exited_with 1 && printed "$1" && no_index && dpkg_status_is "${status_before}" && nothing_ran
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2.
refuses_control() {
  run_install PATH="${STUB_PATH}" PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}"
}

# Neither the package manager nor shell text in a value ran.
nothing_ran() {
  if [[ -e /tmp/manager-called || -e /tmp/pwned ]]; then
    echo "apt-get was called, or a command in a value ran" >&2
    return 1
  fi
}

status_before="$(dpkg_status)"
configuration_before="$(apt_configuration)"

for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/apt-get
chmod +x /tmp/stub/apt-get

for control in "${INVALID_CONTROLS[@]}"; do
  check "'${control#* }' fails with status 1 and names ${control%% *}, with an empty list" \
    refuses_control "${control}" ""
  check "'${control#* }' fails with status 1 and names ${control%% *}, with the list bc" \
    refuses_control "${control}" "bc"
done

for cleanup in all packages none; do
  run_install PATH="${STUB_PATH}" PACKAGES=$' ,\t, ' CLEANUP="${cleanup}"
  check "a list of commas and whitespace succeeds with cleanup=${cleanup}" exited_with 0
done
for timeout in "" 1 3600; do
  run_install PATH="${STUB_PATH}" PACKAGES="" NETWORKTIMEOUT="${timeout}"
  check "an empty list succeeds with networkTimeout='${timeout}'" exited_with 0
done
for control in "${VALID_CONTROLS[@]}"; do
  run_install PATH="${STUB_PATH}" PACKAGES="" "${control}"
  check "an empty list succeeds with ${control}" exited_with 0
done

check "no run called apt-get or ran shell text from a value" nothing_ran
check "no run changed an installed package" dpkg_status_is "${status_before}"
check "no run changed the apt configuration" apt_configuration_is "${configuration_before}"

reportResults
