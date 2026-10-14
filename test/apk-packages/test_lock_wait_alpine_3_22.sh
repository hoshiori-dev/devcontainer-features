#!/bin/sh
# Scenario test_lock_wait_alpine_3_22 (scenarios.json): this script runs install.sh while a second process holds
# apk's database lock /lib/apk/db/lock for a time the script chooses. Spec scenarios "Lock wait is requested", "Native
# lock behavior is inherited" (a held lock fails the run), "Lock released within the wait", and "Lock held beyond the
# wait".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

configuration_before="$(apk_configuration)"
state_before="$(apk_state)"

hold_apk_lock 5
run_install PACKAGES=tree
wait
check "with lockTimeout omitted a run fails while another process holds the lock" install_failed
check "the failure is apk's own report about the lock" output_matches 'Unable to lock database'
check "tree is not installed" not_installed tree
check "the run changed neither apk's world nor its installed database" apk_state_is "${state_before}"

# The lock is taken after the clock is read and held for 4 seconds, so a run that waited for it ends 4 seconds later
# or more.
started="$(date +%s)"
hold_apk_lock 4
run_install PACKAGES=tree LOCKTIMEOUT=60
finished="$(date +%s)"
wait
check "with lockTimeout=60 a run succeeds when the lock is released after 4 seconds" exited_with 0
check "the run waited for the release" test "$((finished - started))" -ge 4
check "tree is installed" installed tree
check "tree is a line of apk's world" in_world tree

# The lock stays held for 15 seconds, far beyond the wait of 2: a run that ended only at the release would succeed.
state_before="$(apk_state)"
hold_apk_lock 15
started="$(date +%s)"
run_install PACKAGES=pv LOCKTIMEOUT=2
finished="$(date +%s)"
wait
check "with lockTimeout=2 a run fails when the lock is held for 15 seconds" install_failed
check "the run did not fail before 2 seconds had passed" test "$((finished - started))" -ge 2
check "the run failed before the lock was released" test "$((finished - started))" -lt 15
check "pv is not installed" not_installed pv
check "the failed run changed neither apk's world nor its installed database" apk_state_is "${state_before}"
check "no run changed the apk configuration" apk_configuration_is "${configuration_before}"

reportResults
