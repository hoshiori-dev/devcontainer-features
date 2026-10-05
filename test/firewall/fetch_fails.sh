#!/bin/bash
# Scenario fetch-fails: default options (failureMode closed). After the first start it re-runs the
# start-time script as root three times: with a table of the test's own dropping outbound HTTPS, so
# the GitHub fetch times out (Fetch fails, Omitted failureMode, Failed start leaves only the
# resolvers, Failure reported as an error, and the script's time bound); without CAP_NET_ADMIN after
# the feature's table is deleted (Rules cannot be loaded); and while an unprivileged process holds
# 127.0.0.1:53 (Resolver port taken). The dropped fetch never reaches GitHub.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the first start is recorded as applied" record_current applied
check "the start check passes" check_passes

# error_with_reason PATTERN: the start check exits non-zero and prints an error naming PATTERN on
# standard error (Failure reported as an error).
error_with_reason() {
  stderr=$("$SHARE/check.sh" 2>&1 >/dev/null)
  status=$?
  echo "$stderr"
  [ "$status" != 0 ] && printf '%s\n' "$stderr" | grep -q "error:.*$1"
}

# Fetch fails
nft -f - <<'EOF'
table inet firewall-test {
  chain out {
    type filter hook output priority -10; policy accept;
    tcp dport 443 drop
  }
}
EOF
started=$(date +%s)
rerun
elapsed=$(($(date +%s) - started))
check "the start-time script ends within 60 seconds (took ${elapsed}s)" test "$elapsed" -lt 60
fetch_failure_recorded() {
  record_current failed && record_field reason | grep -q 'api.github.com/meta'
}
check "the start is recorded as failed, naming the fetch" fetch_failure_recorded
check "the closed table is left" closed_table
check "resolv.conf names the recorded resolvers" names_recorded_resolvers
check "names still resolve" resolves github.com
check "github.com on port 80 refused" refused http://github.com/
check "the start check fails with the fetch as its reason (failureMode closed)" \
  error_with_reason 'the start failed:.*api.github.com/meta'
nft delete table inet firewall-test

# Rules cannot be loaded
nft delete table inet firewall
setpriv --inh-caps=-net_admin --ambient-caps=-net_admin --bounding-set=-net_admin "$SHARE/apply.sh"
check "without CAP_NET_ADMIN the start is recorded as not applied" record_current not-applied
check "no rule of the feature is in place" no_table
check "outbound traffic is unrestricted" reachable https://registry.npmjs.org/
check "the start check fails with the not-applied reason" error_with_reason 'no rule could be loaded'

# Resolver port taken (the previous run stopped the resolver)
check "an unprivileged process holds 127.0.0.1:53" hold_resolver_port
rerun
resolver_failure_recorded() {
  record_current failed && record_field reason | grep -q 'resolver'
}
check "the start is recorded as failed, naming the resolver" resolver_failure_recorded
check "the closed table is loaded" closed_table
check "resolv.conf names the recorded resolvers, not the port holder" names_recorded_resolvers
check "names still resolve" resolves github.com
check "github.com on port 80 refused" refused http://github.com/
release_resolver_port

reportResults
