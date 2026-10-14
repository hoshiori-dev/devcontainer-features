#!/usr/bin/env bash
# Scenario test_lock_wait_0 (scenarios.json): this script runs install.sh while a background process holds libzypp's
# system lock. Spec scenarios "Lock released within the wait", "Lock held past the wait fails", "Explicit lock wait
# overrides an inherited one", and "Native lock wait is inherited" (without a wait libzypp fails at once, and a wait
# of the build environment stays in effect). Times are asserted with a lower bound only: libzypp checks the lock
# again after growing pauses, so a wait runs past its value.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# libzypp's lock: the file holds the process id of the lock's holder, and counts while that process runs.
readonly LOCK_FILE="/run/zypp.pid"

holder=""

# Makes a background process hold libzypp's lock for $1 seconds.
hold_lock() {
  sleep "$1" &
  holder=$!
  echo "${holder}" >"${LOCK_FILE}"
}

holds_the_lock() {
  kill -0 "${holder}" 2>/dev/null
}

released_the_lock() {
  if holds_the_lock; then
    echo "the process ${holder} still holds the lock" >&2
    return 1
  fi
}

# Ends the background process; libzypp ignores a lock file whose process is gone.
release_lock() {
  kill "${holder}"
  wait "${holder}" || true
}

database_before="$(rpm_database)"

hold_lock 120
run_install PACKAGES=bc
check "with an empty lockTimeout and the lock held the feature fails" failed
check "zypper reports the lock" printed "System management is locked"
check "without a lock wait the feature fails at once, long before the lock is released" took_less_than 60
check "the lock is still held when the feature has failed" holds_the_lock

run_install PACKAGES=bc LOCKTIMEOUT=3
check "with lockTimeout=3 and the lock held for longer the feature fails" failed
check "with lockTimeout=3 the feature waits at least 3 seconds" took_at_least 3
check "the lock is still held when the wait is over" holds_the_lock
check "no bc is installed" not_installed bc

run_install PACKAGES=bc LOCKTIMEOUT=2 ZYPP_LOCK_TIMEOUT=3600
check "lockTimeout=2 beside a lock wait of 3600 in the build environment fails as lockTimeout says" failed
check "with lockTimeout=2 the feature waits at least 2 seconds" took_at_least 2
check "the lock is still held: the feature did not wait as the build environment says" holds_the_lock
check "no run without the lock changed an installed package" rpm_database_is "${database_before}"
release_lock

hold_lock 6
run_install PACKAGES=bc LOCKTIMEOUT=600
check "with lockTimeout=600 and the lock released after 6 seconds the feature succeeds" exited_with 0
check "the feature waited until the lock was released" released_the_lock
check "bc is installed after the wait" installed bc

hold_lock 6
run_install PACKAGES=tree ZYPP_LOCK_TIMEOUT=600
check "with an empty lockTimeout a lock wait of the build environment stays in effect: the feature succeeds" \
  exited_with 0
check "the feature waited, as the build environment says, until the lock was released" released_the_lock
check "tree is installed after the wait" installed tree

reportResults
