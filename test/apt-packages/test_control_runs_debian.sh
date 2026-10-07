#!/usr/bin/env bash
# Scenario test_control_runs_debian (scenarios.json): this script runs install.sh several times with different
# controls in one container. Spec scenarios "Only package files are cleaned", "Cached metadata is explicitly selected",
# "Later controls apply to the second installation", "Native timeout is inherited", "Explicit timeout reaches network
# operations", and requirement "Clean package caches" for APT's effective archive and index locations.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly SENTINEL="/var/cache/feature-unrelated/sentinel"
readonly CALL_LOG="/tmp/native-args"
readonly LOGGING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly OWNED_LISTS="/tmp/owned-lists"
readonly OWNED_ARCHIVES="/tmp/owned-archives"

sentinel_kept() {
  [[ "$(<"${SENTINEL}")" == keep ]]
}

# Prints the logged apt-get calls that use the network: update and install.
network_calls() {
  grep --extended-regexp '\[(update|install)\]' "${CALL_LOG}"
}

no_network_call_sets_a_timeout() {
  ! network_calls | grep --quiet '[Tt]imeout'
}

# Every network call carries the HTTPS timeout $1.
every_network_call_has_timeout() {
  ! network_calls | grep --invert-match --fixed-strings --quiet "Acquire::https::Timeout=$1"
}

no_network_call_changes_verification_or_retries() {
  ! network_calls | grep --extended-regexp --quiet 'retries|sslverify|allow-untrusted|no-check-certificate'
}

# The directory $1 holds a file whose name matches $2, or with "no" in $3 holds none.
holds() {
  local found
  found="$(as_root find "$1" -name "$2" -print -quit)"
  if [[ "${3-}" == no ]]; then [[ -z "${found}" ]]; else [[ -n "${found}" ]]; fi
}

configuration_before="$(apt_configuration)"
as_root sh -c "mkdir -p ${SENTINEL%/*} && echo keep >${SENTINEL}"

run_install PACKAGES=dc CLEANUP=packages
check "dc installs with cleanup=packages" exited_with 0
check "dc is installed" installed dc
check "cleanup=packages leaves usable metadata" has_index
run_install PACKAGES=dc CLEANUP=none REFRESHPOLICY=never
check "a later run with refreshPolicy=never and cleanup=none succeeds from the kept metadata" exited_with 0
check "refreshPolicy=never uses the index the image holds" printed "using the package index the image already holds"
check "cleanup=none leaves the metadata in place" has_index
# A later default refresh and cleanup work after the earlier choice to keep the cache.
run_install PACKAGES=m4 CLEANUP=all
check "a later run with the default refresh and cleanup=all succeeds" exited_with 0
check "dc, which the earlier list named, is still installed" installed dc
check "m4, which the later list named, is installed" installed m4
check "cleanup=all removes the metadata" no_index
check "no control value is written to the apt configuration" apt_configuration_is "${configuration_before}"
check "a cache directory the feature does not manage is untouched" sentinel_kept

# An apt-get that logs its arguments and then runs the image's apt-get.
mkdir /tmp/bin
cat >/tmp/bin/apt-get <<LOGGER
#!/bin/sh
printf 'CALL' >>${CALL_LOG}
for argument do printf ' [%s]' "\${argument}" >>${CALL_LOG}; done
printf '\n' >>${CALL_LOG}
exec $(command -v apt-get) "\$@"
LOGGER
chmod +x /tmp/bin/apt-get

run_install PATH="${LOGGING_PATH}" PACKAGES=ed NETWORKTIMEOUT=""
check "ed installs with an empty networkTimeout" exited_with 0
check "premise: the run with an empty networkTimeout made network calls" network_calls
check "with an empty networkTimeout no network call sets a timeout" no_network_call_sets_a_timeout
check "with an empty networkTimeout no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries
as_root rm "${CALL_LOG}"
run_install PATH="${LOGGING_PATH}" PACKAGES=ed NETWORKTIMEOUT=1
check "ed installs with networkTimeout=1" exited_with 0
check "premise: the run with networkTimeout=1 made network calls" network_calls
check "with networkTimeout=1 every network call carries the timeout" every_network_call_has_timeout 1
check "with networkTimeout=1 no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries

# The image moves APT's index and archive directories; cleanup follows them.
as_root mkdir -p "${OWNED_LISTS}/partial" "${OWNED_ARCHIVES}/partial"
printf 'Dir::State::lists "%s";\nDir::Cache::archives "%s";\n' "${OWNED_LISTS}" "${OWNED_ARCHIVES}" \
  | as_root tee /etc/apt/apt.conf.d/99-test-directories >/dev/null
configuration_before="$(apt_configuration)"
run_install PACKAGES=pv CLEANUP=packages
check "pv installs with relocated APT directories and cleanup=packages" exited_with 0
check "cleanup=packages leaves the index in the relocated directory" holds "${OWNED_LISTS}" '*_Packages*'
check "cleanup=packages removes the package files from the relocated archive directory" \
  holds "${OWNED_ARCHIVES}" '*.deb' no
run_install PACKAGES=time CLEANUP=all REFRESHPOLICY=never
check "time installs from the relocated index with refreshPolicy=never and cleanup=all" exited_with 0
check "cleanup=all removes the index from the relocated directory" holds "${OWNED_LISTS}" '*_Packages*' no
check "a cache directory the feature does not manage is still untouched" sentinel_kept
check "the apt configuration is unchanged" apt_configuration_is "${configuration_before}"

reportResults
