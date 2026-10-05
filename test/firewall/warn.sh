#!/usr/bin/env bash
# Scenario "warn": failureMode warn, presets npm, so no start fetches from GitHub. The harness cannot start a
# container whose start fails, so after the first start this test stops the feature's resolver, lets an unprivileged
# process hold 127.0.0.1:53, and runs the start-time script again as root ("Failed start removes the rules", "Failure
# reported as a warning").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

# The process that hold_resolver_port starts.
holder_pid=""

# Stops the feature's resolver and waits until 127.0.0.1:53 is free, as /proc/net/udp writes that address.
stop_resolver() {
  local pid
  local naps=0
  pid="$(cat /run/firewall/dnsmasq.pid)"
  kill "${pid}"
  while awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp; do
    if ((naps >= 50)); then
      echo "the resolver still holds 127.0.0.1:53 after 5 seconds" >&2
      return 1
    fi
    sleep 0.1
    naps=$((naps + 1))
  done
}

# Starts an unprivileged process that binds 127.0.0.1:53, UDP and TCP, for two minutes, sets holder_pid, and waits
# until the port is bound. Docker lets unprivileged processes bind low ports.
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

# Whether the current start is recorded as failed, with the resolver that could not start as its reason. Prints the
# reason; dnsmasq's own message follows the prefix.
failure_recorded_with_reason() {
  local reason
  record_current failed || return 1
  reason="$(record_field reason)" || return 1
  printf 'reason: %s\n' "${reason}"
  [[ "${reason}" == "the resolver (dnsmasq) could not start: "* ]]
}

# Whether the start check exits zero and prints, on standard error, a warning with the reason of the failed start.
# Prints the warning.
check_warns_with_reason() {
  local report
  report="$("${SHARE}/check.sh" 2>&1 >/dev/null)" || return 1
  printf '%s\n' "${report}"
  [[ "${report}" == "firewall: warning: the firewall is not in force: the start failed: the resolver (dnsmasq) "* ]]
}

check "the current start is recorded as applied" record_current applied
check "the check exits zero" check_passes
check "after the applied start, a connection to github.com, which the npm preset does not allow, is refused" \
  refused https://github.com/

stop_resolver
hold_resolver_port
"${SHARE}/apply.sh"

# Failed start removes the rules
check "the start is recorded as failed with its reason" failure_recorded_with_reason
check "the feature leaves no rule in place" no_table
check "outbound traffic is unrestricted by the feature: github.com is reachable" reachable https://github.com/
# Requirement: Failure mode
check "a resolver that cannot start leaves /etc/resolv.conf naming the container's own resolvers" \
  names_recorded_resolvers

# Failure reported as a warning
check "the check prints a warning with the reason on standard error and exits zero" check_warns_with_reason
kill "${holder_pid}"

reportResults
