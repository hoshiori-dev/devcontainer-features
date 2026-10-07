#!/usr/bin/env bash
# Scenario fail_refused_input_0 (scenarios.json): the container has no network, the feature is installed with an empty
# list, and this script then runs install.sh with input that validation refuses and with a PATH that holds no zypper.
# Spec scenarios "URL or path is refused", "Package file name is refused", "Option-like or modifier entry is refused",
# "Kind or repository prefix is refused", "Shell metacharacters and inner whitespace are refused", "Invalid control
# fails before any change", "Empty list ignores installation controls", "Image without zypper fails clearly", and
# "Empty list is a no-op" without zypper; and requirement "Entries are validated before anything changes" for an
# operator without an edition and for more than one operator.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.rpm" "https://example.invalid/bc"
  # Package file name
  "bc.rpm"
  # Option-like or modifier entry
  "--help" "+bc" "!bc" "~bc"
  # Kind or repository prefix
  "pattern:base" "repo:bc"
  # Shell metacharacters and inner whitespace
  "bc file" "bc;echo bad" "b*" "évil"
  # An operator without an edition, and more than one operator
  "bc=" "bc<=" "bc==1" "bc<1>2"
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=(
  "cleanup CLEANUP=invalid" "cleanup CLEANUP="
  "refreshPolicy REFRESHPOLICY=invalid" "refreshPolicy REFRESHPOLICY="
  "installRecommends INSTALLRECOMMENDS=yes" "installRecommends INSTALLRECOMMENDS="
)

# A PATH on which zypper is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"
# A PATH that holds sed and tr, which install.sh may call, and no zypper.
readonly NO_ZYPPER_PATH="/tmp/no-manager"

# The entry $1 is refused with status 1 and named, and nothing changed: no metadata was loaded and no package changed.
# The valid entry file runs beside it, so a gap in the validation would install something.
refuses_entry() {
  run_install PACKAGES="file,$1"
  exited_with 1 && printed "$1" && no_metadata && rpm_database_is "${database_before}"
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2.
refuses_control() {
  run_install PATH="${STUB_PATH}" PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}"
}

zypper_was_not_called() {
  if [[ -e /tmp/manager-called ]]; then
    echo "zypper was called" >&2
    return 1
  fi
}

database_before="$(rpm_database)"
configuration_before="$(zypp_configuration)"

for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/zypper
chmod +x /tmp/stub/zypper

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

check "no run with an invalid control or an empty list called zypper" zypper_was_not_called
check "no run with an invalid control or an empty list changed the zypp configuration" \
  zypp_configuration_is "${configuration_before}"

mkdir "${NO_ZYPPER_PATH}"
for tool in sed tr; do
  ln -s "$(command -v "${tool}")" "${NO_ZYPPER_PATH}/${tool}"
done
run_install PATH="${NO_ZYPPER_PATH}" PACKAGES=""
check "without zypper on PATH an empty list exits with status 0" exited_with 0
run_install PATH="${NO_ZYPPER_PATH}" PACKAGES=bc
check "without zypper on PATH the list bc exits with status 1" exited_with 1
check "the message says that zypper was not found" printed "zypper was not found"
check "the message names openSUSE" printed "openSUSE"
check "the runs without zypper changed no zypp configuration" zypp_configuration_is "${configuration_before}"

check "no run loaded metadata" no_metadata
check "no run changed an installed package" rpm_database_is "${database_before}"

reportResults
