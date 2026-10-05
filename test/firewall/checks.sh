# shellcheck shell=sh
# Sourced by every firewall test: the assertions more than one test script uses, and a POSIX stand-in for
# dev-container-features-test-lib with the same check / reportResults interface. test.sh and duplicate.sh run on
# alpine:3.24, which ships no bash, so they cannot source that library, which is bash; the scenario scripts, bash on
# debian:12, source the library first and this file after it. POSIX sh for that reason.
#
# Tests connect only to the hosts the design's URL inventory marks for tests: github.com, api.github.com,
# raw.githubusercontent.com, and registry.npmjs.org. Addresses the rules refuse (192.0.2.1, 8.8.8.8 on port 53) are
# never reached.

readonly SHARE="/usr/local/share/firewall"
readonly RECORD="/run/firewall/status"

# check and reportResults are defined only when dev-container-features-test-lib has not defined them: a scenario
# script sources that library before this file and keeps the library's two functions.
if ! command -v reportResults >/dev/null 2>&1; then
  failed_checks=""

  # Runs a command and records the label when it fails: check <label> <command> [args...]. Returns 1 after a failure,
  # as the library does, so a test under set -e stops at its first failed check.
  check() {
    check_label="$1"
    shift
    printf "\nTesting '%s'\n" "${check_label}"
    if "$@"; then
      printf "Passed '%s'\n" "${check_label}"
      return 0
    fi
    printf "FAILED '%s'\n" "${check_label}" >&2
    failed_checks="${failed_checks}
  - ${check_label}"
    return 1
  }

  # Lists the failed labels and exits 1, or exits 0 when every check passed. The camelCase name is the library's.
  reportResults() {
    if [ -n "${failed_checks}" ]; then
      printf '\nFailed tests:%s\n' "${failed_checks}" >&2
      exit 1
    fi
    printf '\nTest Passed!\n'
    exit 0
  }
fi

# Runs a command as root: directly when the test already runs as root, else through the passwordless sudo that vscode
# has on base:ubuntu24.04.
as_root() {
  as_root_uid="$(id -u)"
  if [ "${as_root_uid}" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# Whether a request with the curl arguments $@ completes, whatever its HTTP status.
reachable() {
  curl -q -sS -o /dev/null --connect-timeout 10 --max-time 30 "$@"
}

# Whether every connection attempt of a request with the curl arguments $@ is refused: curl ends with status 7, an
# error and not a timeout. A name with several addresses takes one attempt per address, which the curl of debian:12
# spreads over several seconds, so the bounds are wide; test.sh times a single refusal.
refused() {
  if curl -q -sS -o /dev/null --connect-timeout 10 --max-time 15 "$@"; then
    return 1
  else
    refused_status=$?
  fi
  [ "${refused_status}" -eq 7 ]
}

# Prints the first IPv4 address that a lookup of the name $1 through the container's resolver returns; fails when it
# returns none.
first_address() {
  first_address_answer="$(getent ahosts "$1")" || return 1
  awk '$1 ~ /^[0-9.]+$/ { print $1; found = 1; exit } END { exit !found }' <<EOF
${first_address_answer}
EOF
}

# Whether a lookup of the name $1 returns an address.
resolves() {
  first_address "$1" >/dev/null
}

# Whether raw.githubusercontent.com is reachable at the address $1, without a lookup.
raw_at() {
  reachable --resolve "raw.githubusercontent.com:443:$1" https://raw.githubusercontent.com/
}

# Whether a connection to raw.githubusercontent.com at the address $1, without a lookup, is refused.
raw_refused_at() {
  refused --resolve "raw.githubusercontent.com:443:$1" https://raw.githubusercontent.com/
}

# Prints the value of the field $1 of the start record.
record_field() {
  sed -n "s/^$1=//p" "${RECORD}"
}

# Whether the field $1 of the start record has the value $2.
record_is() {
  record_is_value="$(record_field "$1")" || return 1
  [ "${record_is_value}" = "$2" ]
}

# Prints the start time of the container's PID 1, by which apply.sh marks the record of the current start.
current_start() {
  current_start_stat="$(cat /proc/1/stat)" || return 1
  # The start time is the twentieth field after the command name, which stands in parentheses and may hold spaces.
  awk '{ print $20 }' <<EOF
${current_start_stat##*) }
EOF
}

# Whether the start record belongs to the current start and names the result $1.
record_current() {
  record_current_start="$(current_start)" || return 1
  record_is start "${record_current_start}" && record_is result "$1"
}

# Whether the start check, run as the dev container tool runs it, exits zero.
check_passes() {
  "${SHARE}/check.sh"
}

# Prints the feature's table as nft lists it.
table_listing() {
  as_root nft list table inet firewall
}

# Whether the feature's table does not exist.
no_table() {
  if as_root nft list table inet firewall >/dev/null 2>&1; then return 1; fi
}

# Prints the nameserver addresses of /etc/resolv.conf on one line, separated by spaces, as apply.sh records them.
nameservers() {
  awk '$1 == "nameserver" { printf "%s%s", separator, $2; separator = " " } END { print "" }' /etc/resolv.conf
}

# Whether /etc/resolv.conf names the resolvers the feature recorded for this container, which are Docker's and so
# known only when the test runs.
names_recorded_resolvers() {
  names_recorded_resolvers_named="$(nameservers)" || return 1
  names_recorded_resolvers_recorded="$(cat /var/lib/firewall/resolvers)" || return 1
  [ "${names_recorded_resolvers_named}" = "${names_recorded_resolvers_recorded}" ]
}

# Whether /etc/resolv.conf names the feature's resolver and no other.
names_local_resolver() {
  names_local_resolver_named="$(nameservers)" || return 1
  [ "${names_local_resolver_named}" = "127.0.0.1" ]
}

# Whether the nested Docker daemon that docker-in-docker starts answers within 60 seconds.
wait_for_docker() {
  wait_for_docker_seconds=0
  until docker info >/dev/null 2>&1; do
    if [ "${wait_for_docker_seconds}" -ge 60 ]; then return 1; fi
    sleep 1
    wait_for_docker_seconds=$((wait_for_docker_seconds + 1))
  done
}
