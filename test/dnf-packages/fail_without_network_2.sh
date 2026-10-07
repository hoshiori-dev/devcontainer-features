#!/usr/bin/env bash
# Scenario fail_without_network_2 (scenarios.json): the feature is installed with an empty list, the container has no
# network, and this script then runs install.sh with input that validation refuses, with dnf hidden from PATH, and with
# refreshPolicy=never while the image holds no repository metadata. Spec scenarios "URL or path is refused", "Package
# file name is refused", "Option-like entry is refused", "Group, module, and dependency expressions are refused", "Shell
# metacharacters, globs, and inner whitespace are refused", "Invalid control fails before any change", "Empty list
# ignores installation controls", "Timeout boundaries are validated", "Empty list is a no-op" and "Image without dnf
# fails clearly" (both with a PATH that holds no dnf), and "Missing cached metadata fails without refresh".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.rpm" "https://example.invalid/bc"
  # Package file name
  "bc.rpm" "bc.RPM"
  # Option-like entry
  "--help"
  # Group, module, and dependency expressions
  "@core" "module:stream/profile" "bc>=1" "(bc)"
  # Shell metacharacters, globs, and inner whitespace
  "bc file" "bc;echo bad" "b*" "évil"
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=(
  "cleanup CLEANUP=invalid" "cleanup CLEANUP="
  "refreshPolicy REFRESHPOLICY=invalid" "refreshPolicy REFRESHPOLICY="
  "installWeakDeps INSTALLWEAKDEPS=yes" "installWeakDeps INSTALLWEAKDEPS="
  "networkTimeout NETWORKTIMEOUT=0" "networkTimeout NETWORKTIMEOUT=3601" "networkTimeout NETWORKTIMEOUT=01"
  "networkTimeout NETWORKTIMEOUT=-1" "networkTimeout NETWORKTIMEOUT=+1" "networkTimeout NETWORKTIMEOUT=1 "
  "networkTimeout NETWORKTIMEOUT=1.5" "networkTimeout NETWORKTIMEOUT=１２"
  "networkTimeout NETWORKTIMEOUT=\$(touch /tmp/pwned)" "networkTimeout NETWORKTIMEOUT=999999999999999999999999"
)

# A PATH on which dnf is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"
# A PATH that holds sed and tr and no dnf.
readonly NO_DNF_PATH="/tmp/no-manager"

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

# dnf and the other package managers print one of these texts when they fetch repository metadata.
attempted_no_download() {
  if output_matches 'fetch https?:|Downloading|Retrieving repository'; then
    echo "dnf tried to fetch metadata" >&2
    return 1
  fi
}

# Neither the package manager nor shell text in a value ran.
nothing_ran() {
  if [[ -e /tmp/manager-called || -e /tmp/pwned ]]; then
    echo "dnf was called, or a command in a value ran" >&2
    return 1
  fi
}

database_before="$(rpm_database)"
configuration_before="$(dnf_configuration)"

for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/dnf
chmod +x /tmp/stub/dnf

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

check "no run called dnf or ran shell text from a value" nothing_ran
check "no run loaded repository metadata" no_metadata
check "no run changed an installed package" rpm_database_is "${database_before}"
check "no run changed the dnf configuration" dnf_configuration_is "${configuration_before}"

mkdir "${NO_DNF_PATH}"
for tool in sed tr; do
  ln -s "$(command -v "${tool}")" "${NO_DNF_PATH}/${tool}"
done

run_install PATH="${NO_DNF_PATH}" PACKAGES=""
check "without dnf on PATH an empty list exits with status 0" exited_with 0
run_install PATH="${NO_DNF_PATH}" PACKAGES=bc
check "without dnf on PATH the list bc exits with status 1" exited_with 1
check "the message says that dnf was not found" printed "dnf was not found"
check "the message names Fedora and RHEL-compatible images" printed "Fedora or RHEL-compatible"
check "the runs without dnf on PATH changed no installed package" rpm_database_is "${database_before}"
check "the runs without dnf on PATH changed no dnf configuration" dnf_configuration_is "${configuration_before}"

# The runs above left the image without repository metadata, and nothing can be downloaded.
check "premise: the image holds no repository metadata" no_metadata
run_install PACKAGES=bc REFRESHPOLICY=never CLEANUP=packages
check "refreshPolicy=never without cached metadata exits with a non-zero status" failed
check "refreshPolicy=never without cached metadata attempts no download" attempted_no_download
check "refreshPolicy=never without cached metadata does not install bc" not_installed bc
check "refreshPolicy=never without cached metadata changes no installed package" rpm_database_is "${database_before}"
check "refreshPolicy=never without cached metadata leaves the dnf configuration unchanged" \
  dnf_configuration_is "${configuration_before}"

reportResults
