#!/bin/sh
# Install-twice test ("Different options the second time"): firewall is installed first with the non-default options
# the dev container CLI derives from the metadata (defaultAction allow, presets npm, failureMode warn, filterForward
# false), then with the defaults (deny, github, closed, true). The values arrive as <OPTION> and <OPTION>__DEFAULT.
# POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The CLI gives the first install the second value of an option's enum or proposals, and the second install the
# default.
first_install_used_other_options() {
  [ "${DEFAULTACTION}" = "allow" ] && [ "${DEFAULTACTION__DEFAULT}" = "deny" ] \
    && [ "${PRESETS}" = "npm" ] && [ "${PRESETS__DEFAULT}" = "github" ]
}

options_file_holds_defaults() {
  cat "${SHARE}/options"
  grep -qx defaultAction=deny "${SHARE}/options" && grep -qx presets=github "${SHARE}/options" \
    && grep -qx failureMode=closed "${SHARE}/options" && grep -qx filterForward=true "${SHARE}/options"
}

defaults_recorded() {
  record_is defaultAction deny && record_is presets github && record_is failureMode closed \
    && record_is filterForward true
}

forward_filtered() {
  forward_filtered_table="$(table_listing)" || return 1
  case "${forward_filtered_table}" in
    *"hook forward"*) ;;
    *) return 1 ;;
  esac
}

# Deviation from shell-style.md (Tests): this label states the premise of the test, which is no behavior of the spec
# (the design's Open Questions 13). Without it, a first install with the defaults would let every check below pass.
check "premise: the first install used defaultAction allow and presets npm, the second deny and github" \
  first_install_used_other_options

# Different options the second time
check "the options file holds only the second install's options" options_file_holds_defaults
check "the current start is recorded as applied" record_current applied
check "the start record names only the second install's options" defaults_recorded
check "forwarded traffic is filtered, as the second install's filterForward true states" forward_filtered
check "the check exits zero" check_passes
check "github.com, which the second install's github preset allows, is reachable" reachable https://github.com/
check "registry.npmjs.org, which only the first install's npm preset and defaultAction allow let through, is refused" \
  refused https://registry.npmjs.org/

reportResults
