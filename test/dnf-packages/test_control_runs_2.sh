#!/usr/bin/env bash
# Scenario test_control_runs_2 (scenarios.json): this script runs install.sh several times with different controls in
# one container. Spec scenarios "Only package files are cleaned", "Cached metadata is explicitly selected", "Later
# controls apply to the second installation", "Native timeout is inherited", "Explicit timeout reaches network
# operations", and "Cache-only package miss fails".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly SENTINEL="/var/cache/feature-unrelated/sentinel"
readonly CALL_LOG="/tmp/native-args"
readonly LOGGING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"

sentinel_kept() {
  [[ "$(<"${SENTINEL}")" == keep ]]
}

# Prints the logged dnf calls that use the network: install.
network_calls() {
  grep --fixed-strings '[install]' "${CALL_LOG}"
}

no_network_call_sets_a_timeout() {
  ! network_calls | grep --quiet '[Tt]imeout'
}

# Every network call carries the timeout $1 for every repository.
every_network_call_has_timeout() {
  ! network_calls | grep --invert-match --fixed-strings --quiet -e "--setopt=*.timeout=$1"
}

no_network_call_changes_verification_or_retries() {
  ! network_calls | grep --extended-regexp --quiet 'retries|sslverify|allow-untrusted|no-check-certificate'
}

configuration_before="$(dnf_configuration)"
mkdir -p "${SENTINEL%/*}"
echo keep >"${SENTINEL}"

run_install PACKAGES=bc CLEANUP=packages
check "bc installs with cleanup=packages" exited_with 0
check "bc is installed" installed bc
check "cleanup=packages leaves usable metadata" has_metadata
run_install PACKAGES=bc CLEANUP=none REFRESHPOLICY=never
check "a later run with refreshPolicy=never and cleanup=none succeeds from the kept metadata" exited_with 0
check "cleanup=none leaves the metadata in place" has_metadata
# A later default refresh and cleanup work after the earlier choice to keep the cache.
run_install PACKAGES=file CLEANUP=all
check "a later run with the default refresh and cleanup=all succeeds" exited_with 0
check "bc, which the earlier list named, is still installed" installed bc
check "file, which the later list named, is installed" installed file
check "cleanup=all removes the metadata" no_metadata
check "no control value is written to the dnf configuration" dnf_configuration_is "${configuration_before}"
check "a cache directory the feature does not manage is untouched" sentinel_kept

# A dnf that logs its arguments and then runs the image's dnf.
mkdir /tmp/bin
cat >/tmp/bin/dnf <<LOGGER
#!/bin/sh
printf 'CALL' >>${CALL_LOG}
for argument do printf ' [%s]' "\${argument}" >>${CALL_LOG}; done
printf '\n' >>${CALL_LOG}
exec $(command -v dnf) "\$@"
LOGGER
chmod +x /tmp/bin/dnf

run_install PATH="${LOGGING_PATH}" PACKAGES=tree NETWORKTIMEOUT=""
check "tree installs with an empty networkTimeout" exited_with 0
check "premise: the run with an empty networkTimeout made network calls" network_calls
check "with an empty networkTimeout no network call sets a timeout" no_network_call_sets_a_timeout
check "with an empty networkTimeout no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries
rm "${CALL_LOG}"
run_install PATH="${LOGGING_PATH}" PACKAGES=tree NETWORKTIMEOUT=1
check "tree installs with networkTimeout=1" exited_with 0
check "premise: the run with networkTimeout=1 made network calls" network_calls
check "with networkTimeout=1 every network call carries the timeout" every_network_call_has_timeout 1
check "with networkTimeout=1 no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries

# cleanup=packages leaves the metadata and no package file, so a package that is not installed has no cached payload.
run_install PACKAGES=ed CLEANUP=packages
check "ed installs with cleanup=packages" exited_with 0
check "premise: the image holds repository metadata" has_metadata
check "premise: time is not installed" not_installed time
configuration_before="$(dnf_configuration)"
run_install PACKAGES=time REFRESHPOLICY=never CLEANUP=none
check "refreshPolicy=never fails for time, whose package file is not cached" failed
check "refreshPolicy=never downloads and installs no package: time is not installed" not_installed time
check "the failed run leaves the dnf configuration unchanged" dnf_configuration_is "${configuration_before}"

reportResults
