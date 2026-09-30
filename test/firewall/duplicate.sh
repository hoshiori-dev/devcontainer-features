#!/bin/sh
# Install-twice test: firewall is installed once with the non-default options the CLI derives from
# the metadata (defaultAction allow, presets npm, failureMode warn, filterForward false) and once with
# the defaults, which install last. Option values arrive as <OPTION> and <OPTION>__DEFAULT env vars.
# Different options the second time: only the second install's options are in effect at start.
# POSIX sh: Alpine ships no bash (helpers.sh).

# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the first install used other options" test "${DEFAULTACTION-}" != "${DEFAULTACTION__DEFAULT-}" \
  -a "${PRESETS-}" != "${PRESETS__DEFAULT-}"

stored_defaults() {
  cat "$SHARE/options"
  grep -qx defaultAction=deny "$SHARE/options" && grep -qx presets=github "$SHARE/options" \
    && grep -qx failureMode=closed "$SHARE/options" && grep -qx filterForward=true "$SHARE/options"
}
check "the options file holds the defaults" stored_defaults
check "the current start is recorded as applied" record_current applied
recorded_defaults() {
  record_is defaultAction deny && record_is presets github && record_is failureMode closed \
    && record_is filterForward true
}
check "the start applied the defaults" recorded_defaults
forward_filtered() {
  table_listing | grep -q 'hook forward'
}
check "forwarded traffic is filtered (filterForward true)" forward_filtered
check "the start check passes" check_passes
check "github.com reachable (github preset)" reachable https://github.com/
check "registry.npmjs.org refused (the first install's npm preset and allow are gone)" \
  refused https://registry.npmjs.org/

reportResults
