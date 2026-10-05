#!/usr/bin/env bash
# Scenario "fetch_fails": default options (the github preset, failureMode closed). The harness cannot start a
# container whose start fails, so after the first start this test runs the start-time script again as root, three
# times: while a table of the test's own drops outbound HTTPS, so that the GitHub fetch times out without reaching
# GitHub ("Fetch fails", "Omitted failureMode", "Failed start leaves only the resolvers", "Failure reported as an
# error"); without CAP_NET_ADMIN, after the feature's table is deleted ("Rules cannot be loaded"); and while an
# unprivileged process holds 127.0.0.1:53 ("Resolver port taken").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

# The process that hold_resolver_port starts.
holder_pid=""

# Starts an unprivileged process that binds 127.0.0.1:53, UDP and TCP, for two minutes, sets holder_pid, and waits
# until the port is bound, as /proc/net/udp writes that address. Docker lets unprivileged processes bind low ports.
hold_resolver_port() {
  local naps=0
  # The single quotes hold a perl program; its variables are perl's, not the shell's.
  # shellcheck disable=SC2016
  setpriv --reuid=65534 --regid=65534 --clear-groups perl -MSocket -e '
    socket(my $udp, PF_INET, SOCK_DGRAM, 0) or die "socket: $!";
    bind($udp, pack_sockaddr_in(53, inet_aton("127.0.0.1"))) or die "bind: $!";
    socket(my $tcp, PF_INET, SOCK_STREAM, 0) or die "socket: $!";
    bind($tcp, pack_sockaddr_in(53, inet_aton("127.0.0.1"))) or die "bind: $!";
    listen($tcp, 5) or die "listen: $!";
    sleep 120' &
  holder_pid=$!
  until awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp; do
    if ((naps >= 50)); then
      echo "no process holds 127.0.0.1:53 after 5 seconds" >&2
      return 1
    fi
    sleep 0.1
    naps=$((naps + 1))
  done
}

# Whether the feature's table is the closed one, which lets only loopback, replies, and DNS to the resolvers through:
# it has none of what the other rulesets add, which are the learned sets, the rule for the nested bridges, and the
# rule for the probe address of the full table, and the HTTPS rule for api.github.com of the table used for the fetch.
closed_table() {
  local table
  table="$(table_listing)" || return 1
  [[ "${table}" != *learned* && "${table}" != *docker0* && "${table}" != *"daddr 192.0.2.1"* \
    && "${table}" != *"dport 443"* ]]
}

# Whether the current start is recorded as failed with a reason that starts with $1. Prints the reason.
failure_recorded() {
  local reason
  record_current failed || return 1
  reason="$(record_field reason)" || return 1
  printf 'reason: %s\n' "${reason}"
  [[ "${reason}" == "$1"* ]]
}

# Whether the start check exits non-zero and reports on standard error that the firewall is not in force, with a
# reason that starts with $1. Prints the report.
check_fails_with() {
  local report
  if report="$("${SHARE}/check.sh" 2>&1 >/dev/null)"; then return 1; fi
  printf '%s\n' "${report}"
  [[ "${report}" == "firewall: error: the firewall is not in force: $1"* ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes

# Fetch fails: the test's table drops every connection to port 443, at a priority before the feature's chain.
nft -f - <<'EOF'
table inet firewall-test {
  chain out {
    type filter hook output priority -10; policy accept;
    tcp dport 443 drop
  }
}
EOF
started="$(date +%s)"
"${SHARE}/apply.sh"
elapsed=$(($(date +%s) - started))
printf 'the start-time script ran for %s seconds\n' "${elapsed}"
# Deviation from shell-style.md (Tests): this label uses the words of the design's Goal "Bounded start", an invariant
# of the approach that no scenario of the spec states.
check "the start-time script ends within 60 seconds when the network is unreachable" test "${elapsed}" -lt 60
# curl's own message follows the prefix.
check "when the fetch times out, the start is recorded as failed with the fetch as its reason" \
  failure_recorded "fetching https://api.github.com/meta failed twice: "

# Omitted failureMode, Failed start leaves only the resolvers
check "the rules left in place let only loopback and the DNS resolvers through" closed_table
check "the DNS resolvers are reachable: github.com resolves" resolves github.com
# Port 80, because the test's own table drops port 443 before the feature's rules see it.
check "a connection to github.com, which the applied rules allowed, is refused" refused http://github.com/
# Deviation from shell-style.md (Tests): this label uses the words of the design's Goal "Resolvers recorded once per
# container", an invariant of the approach that no scenario of the spec states.
check "/etc/resolv.conf names the recorded resolvers while dnsmasq does not run" names_recorded_resolvers

# Failure reported as an error
check "after the failed start, the check prints the reason and exits non-zero" \
  check_fails_with "the start failed: fetching https://api.github.com/meta failed twice: "
nft delete table inet firewall-test

# Rules cannot be loaded
nft delete table inet firewall
setpriv --inh-caps=-net_admin --ambient-caps=-net_admin --bounding-set=-net_admin "${SHARE}/apply.sh"
check "without NET_ADMIN, the start is recorded as not applied" record_current not-applied
check "without NET_ADMIN, no rule of the feature is in place" no_table
check "without NET_ADMIN, outbound traffic is not restricted: registry.npmjs.org, which no option allows, succeeds" \
  reachable https://registry.npmjs.org/
check "after the start that was not applied, the check prints the reason and exits non-zero" \
  check_fails_with "no rule could be loaded: "

# Resolver port taken. No resolver of the feature runs: the two starts above ended before they launched one.
hold_resolver_port
"${SHARE}/apply.sh"
# dnsmasq's own message follows the prefix.
check "when another process holds the resolver's port, the start is recorded as failed" \
  failure_recorded "the resolver (dnsmasq) could not start: "
check "only loopback and the DNS resolvers are reachable: the rules in place are the closed ones" closed_table
check "the DNS resolvers are reachable: github.com resolves" resolves github.com
check "a connection to github.com, which the applied rules allowed, is refused" refused https://github.com/
check "/etc/resolv.conf names the container's own resolvers, not the process that holds the port" \
  names_recorded_resolvers
kill "${holder_pid}"

reportResults
