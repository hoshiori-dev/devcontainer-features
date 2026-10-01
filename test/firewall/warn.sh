#!/bin/bash
# Scenario warn: failureMode warn, presets npm (no GitHub fetch). After the first start it stops the
# resolver, lets an unprivileged process hold 127.0.0.1:53, and re-runs the start-time script as root.
# Covers Failed start removes the rules and Failure reported as a warning.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the first start is recorded as applied" record_current applied
check "the start check passes" check_passes
check "github.com refused (npm preset only)" refused https://github.com/

stop_resolver
check "an unprivileged process holds 127.0.0.1:53" hold_resolver_port
rerun
failure_recorded() {
  record_current failed && [ -n "$(record_field reason)" ]
}
check "the start is recorded as failed with its reason" failure_recorded
check "no rule of the feature is left" no_table
check "resolv.conf names the recorded resolvers" names_recorded_resolvers
check "github.com reachable (no rule in place)" reachable https://github.com/
warning_only() {
  stderr=$("$SHARE/check.sh" 2>&1 >/dev/null)
  status=$?
  echo "$stderr"
  [ "$status" = 0 ] && printf '%s\n' "$stderr" | grep -q 'warning:.*resolver'
}
check "the start check warns with the reason on standard error and exits zero" warning_only
release_resolver_port

reportResults
