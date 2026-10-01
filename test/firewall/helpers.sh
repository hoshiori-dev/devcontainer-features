# shellcheck shell=sh
# Helpers for the firewall tests, sourced by test.sh, duplicate.sh, and every scenario script. POSIX
# sh: test.sh and duplicate.sh run on Alpine, which ships no bash, so they cannot source the bash-only
# dev-container-features-test-lib and use the check and reportResults defined here instead; the
# scenario scripts run on debian:12 and source the library first.
#
# Tests connect only to the hosts design.md's URL inventory marks for tests: github.com,
# api.github.com, raw.githubusercontent.com, and registry.npmjs.org. Addresses the rules refuse
# (192.0.2.1, 8.8.8.8 on port 53) are never reached.

SHARE=/usr/local/share/firewall
RECORD=/run/firewall/status

if ! command -v reportResults >/dev/null 2>&1; then
  FAILED_CHECKS=
  check() {
    check_label=$1
    shift
    printf '\nTesting: %s\n' "$check_label"
    if "$@"; then
      printf 'Passed: %s\n' "$check_label"
      return 0
    fi
    printf 'FAILED: %s\n' "$check_label" >&2
    FAILED_CHECKS="$FAILED_CHECKS
  $check_label"
    return 1
  }
  reportResults() {
    if [ -n "$FAILED_CHECKS" ]; then
      printf '\nFailed tests:%s\n' "$FAILED_CHECKS" >&2
      exit 1
    fi
    printf '\nTest Passed!\n'
    exit 0
  }
fi

# as_root CMD...: runs CMD as root (the remote user of base:ubuntu24.04 has passwordless sudo).
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi
}

# reachable [CURL ARGS] URL: an HTTPS request completes, whatever its HTTP status.
reachable() {
  curl -q -sS -o /dev/null --connect-timeout 10 --max-time 30 "$@"
}

# refused [CURL ARGS] URL: every connection attempt fails with an error, not a timeout. A name with
# many addresses takes one attempt per address, so the bound is generous; timed_refusal is strict.
refused() {
  curl -q -sS -o /dev/null --connect-timeout 10 --max-time 15 "$@"
  [ $? -eq 7 ]
}

# timed_refusal HOST: a connection to one address of HOST on port 443 is refused in under a second.
timed_refusal() {
  timed_address=$(first_address "$1") || return 1
  timed_seconds=$(curl -q -sS -o /dev/null --connect-timeout 5 -w '%{time_total}' \
    --resolve "$1:443:$timed_address" "https://$1/")
  [ $? -eq 7 ] || return 1
  echo "refused after ${timed_seconds}s"
  awk -v t="$timed_seconds" 'BEGIN { exit !(t + 0 < 1) }'
}

# first_address NAME: the first IPv4 address a lookup of NAME through the container's resolver returns.
first_address() {
  getent ahosts "$1" | awk '$1 ~ /^[0-9.]+$/ { print $1; found = 1; exit } END { exit !found }'
}

# resolves NAME: a lookup of NAME returns an address.
resolves() {
  first_address "$1" >/dev/null
}

# raw_at ADDRESS / raw_refused_at ADDRESS: raw.githubusercontent.com on ADDRESS, without a lookup.
raw_at() {
  reachable --resolve "raw.githubusercontent.com:443:$1" https://raw.githubusercontent.com/
}
raw_refused_at() {
  refused --resolve "raw.githubusercontent.com:443:$1" https://raw.githubusercontent.com/
}

# record_field NAME: a field of the start record.
record_field() {
  sed -n "s/^$1=//p" "$RECORD"
}

# record_is NAME VALUE: the start record's field NAME equals VALUE.
record_is() {
  [ "$(record_field "$1")" = "$2" ]
}

# current_start: the start time of PID 1, as apply.sh records it.
current_start() {
  sed 's/.*) //' /proc/1/stat | awk '{ print $20 }'
}

# record_current RESULT: the start record belongs to the current start and names RESULT.
record_current() {
  record_is start "$(current_start)" && record_is result "$1"
}

# rerun: runs the start-time script as root again, as the entrypoint does at a start.
rerun() {
  as_root "$SHARE/apply.sh"
}

# check_passes / check_fails: the start check, as the dev container tool runs it.
check_passes() {
  "$SHARE/check.sh"
}
check_fails() {
  ! "$SHARE/check.sh"
}

# table_listing: the feature's table as nft lists it.
table_listing() {
  as_root nft list table inet firewall
}

# no_table: the feature's table does not exist.
no_table() {
  ! as_root nft list table inet firewall >/dev/null 2>&1
}

# closed_table: the feature's table is the closed one: no learned set, no bridge or range rule.
closed_table() {
  table_listing >/tmp/firewall-table.txt || return 1
  ! grep -q -e learned -e docker0 -e 'daddr 192.0.2.1' /tmp/firewall-table.txt
}

# nameservers: the nameserver addresses of /etc/resolv.conf.
nameservers() {
  awk '$1 == "nameserver" { printf "%s%s", sep, $2; sep = " " } END { print "" }' /etc/resolv.conf
}

# names_recorded_resolvers: /etc/resolv.conf names the recorded resolvers, not the feature's resolver.
names_recorded_resolvers() {
  [ "$(nameservers)" = "$(cat /var/lib/firewall/resolvers)" ]
}

# names_local_resolver: /etc/resolv.conf names only the feature's resolver.
names_local_resolver() {
  [ "$(nameservers)" = 127.0.0.1 ]
}

# stop_resolver: stops the feature's dnsmasq and waits until 127.0.0.1:53 is free.
stop_resolver() {
  stop_pid=$(cat /run/firewall/dnsmasq.pid 2>/dev/null) || return 0
  as_root kill "$stop_pid" 2>/dev/null || return 0
  stop_i=0
  while awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp && [ $stop_i -lt 50 ]; do
    sleep 0.1
    stop_i=$((stop_i + 1))
  done
}

# hold_resolver_port: an unprivileged process binds 127.0.0.1:53 (UDP and TCP) for two minutes;
# its PID goes to /tmp/firewall-holder.pid. Docker lets unprivileged processes bind low ports. Runs
# as root (the scenarios on debian:12), which has setpriv and perl.
hold_resolver_port() {
  # shellcheck disable=SC2016 # a perl program
  setpriv --reuid=65534 --regid=65534 --clear-groups perl -MSocket -e '
    socket(my $u, PF_INET, SOCK_DGRAM, 0) or die "socket: $!";
    bind($u, pack_sockaddr_in(53, inet_aton("127.0.0.1"))) or die "bind: $!";
    socket(my $t, PF_INET, SOCK_STREAM, 0) or die "socket: $!";
    bind($t, pack_sockaddr_in(53, inet_aton("127.0.0.1"))) or die "bind: $!";
    listen($t, 5) or die "listen: $!";
    sleep 120' &
  echo $! >/tmp/firewall-holder.pid
  hold_i=0
  until awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp; do
    hold_i=$((hold_i + 1))
    [ $hold_i -lt 50 ] || return 1
    sleep 0.1
  done
}

# release_resolver_port: ends the process hold_resolver_port started.
release_resolver_port() {
  kill "$(cat /tmp/firewall-holder.pid)" 2>/dev/null || true
}

# wait_for_docker: waits at most 60 seconds for the nested Docker daemon of docker-in-docker.
wait_for_docker() {
  docker_i=0
  until docker info >/dev/null 2>&1; do
    docker_i=$((docker_i + 1))
    [ $docker_i -lt 60 ] || return 1
    sleep 1
  done
}

# nested_setup: imports the dev container's own root file system as the image firewall-test/rootfs
# (so no test pulls from a registry) and creates the user-defined network firewall-test.
nested_setup() {
  tar -C / --one-file-system -cf - --exclude=./proc --exclude=./sys --exclude=./dev --exclude=./tmp \
    --exclude=./var/lib/docker --exclude=./var/cache --exclude=./var/lib/apt --exclude=./usr/share \
    --exclude=./usr/local --exclude=./usr/libexec/docker --exclude='./usr/bin/docker*' \
    --exclude='./usr/bin/containerd*' --exclude=./usr/bin/ctr --exclude=./usr/bin/runc . \
    | docker import - firewall-test/rootfs >/dev/null || return 1
  docker network inspect firewall-test >/dev/null 2>&1 || docker network create firewall-test >/dev/null
}

# nested_curl URL: curl in a nested container on the user-defined network; prints curl's exit status.
nested_curl() {
  docker run --rm --network firewall-test firewall-test/rootfs \
    /usr/bin/curl -q -sS -o /dev/null --connect-timeout 10 --max-time 30 "$1"
  nested_status=$?
  echo "nested curl exit status $nested_status"
  return $nested_status
}

# nested_reachable URL / nested_refused URL: the nested container's request completes, or its
# connection is refused (curl exit status 7).
nested_reachable() {
  nested_curl "$1"
}
nested_refused() {
  nested_curl "$1"
  [ $? -eq 7 ]
}
