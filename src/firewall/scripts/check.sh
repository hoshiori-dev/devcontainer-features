#!/bin/sh
# Start check of the firewall feature: the postStartCommand, run without privilege. It waits at most
# 90 seconds for the record of the current start (/run/firewall/status, written by apply.sh), treats
# a record of an earlier start as missing, and probes 192.0.2.1:443, which the rules refuse whatever
# the options say: only an immediate refusal proves them in force. With failureMode closed a start
# that is not in force exits non-zero; with warn it warns on standard error and exits zero. It sends
# nothing to any host on the Internet, runs under a clean environment with a fixed PATH, and calls
# every tool by absolute path, so the remote user's PATH, ENV, or BASH_ENV cannot change its result.
# POSIX sh: Alpine ships no bash.

if [ "${1-}" != --clean ]; then
  exec /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/sh /usr/local/share/firewall/check.sh --clean
fi
set -u

RECORD=/run/firewall/status
OPTIONS=/usr/local/share/firewall/options
WAIT_SECONDS=90

# field NAME FILE: the value of a NAME=value line of FILE (shell builtins only).
field() {
  [ -r "$2" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in "$1"=*)
      printf '%s\n' "${line#*=}"
      return 0
      ;;
    esac
  done <"$2"
  return 1
}

# pid1_start: the start time of the container's PID 1, as apply.sh records it.
pid1_start() {
  IFS= read -r stat </proc/1/stat || return 1
  set -f
  # shellcheck disable=SC2086 # split the fields after the command name
  set -- ${stat##*) }
  set +f
  [ $# -ge 20 ] || return 1
  shift 19
  printf '%s\n' "$1"
}

MODE=$(field failureMode "$OPTIONS") || MODE=closed
[ "$MODE" = warn ] || MODE=closed

not_in_force() {
  set -- "$*"
  if [ "$MODE" = warn ]; then
    printf 'firewall: warning: the firewall is not in force: %s\n' "$1" >&2
    exit 0
  fi
  printf 'firewall: error: the firewall is not in force: %s\n' "$1" >&2
  printf 'firewall: see %s; failureMode closed keeps only loopback and DNS reachable when rules were loaded\n' \
    "$RECORD" >&2
  exit 1
}

CURRENT=$(pid1_start) || not_in_force "cannot read the start time of PID 1 from /proc/1/stat"
waited=0
while :; do
  if [ "$(field start "$RECORD")" = "$CURRENT" ]; then break; fi
  if [ $waited -ge $WAIT_SECONDS ]; then
    not_in_force "no record of the current start in $RECORD after $WAIT_SECONDS seconds" \
      "(the entrypoint did not run as root)"
  fi
  /bin/sleep 1
  waited=$((waited + 1))
done

RESULT=$(field result "$RECORD")
REASON=$(field reason "$RECORD")
[ -z "$(field failureMode "$RECORD")" ] || MODE=$(field failureMode "$RECORD")
[ "$MODE" = warn ] || MODE=closed
case $RESULT in
  applied) ;;
  failed) not_in_force "the start failed: $REASON" ;;
  not-applied) not_in_force "no rule could be loaded: $REASON" ;;
  *) not_in_force "the start record names no known result (\"$RESULT\")" ;;
esac

PROBE=$(/usr/bin/curl -q -v -sS --connect-timeout 3 --max-time 3 -o /dev/null http://192.0.2.1:443/ 2>&1)
STATUS=$?
case $STATUS:$PROBE in
  7:*"Connection refused"*) ;;
  *) not_in_force "the probe to 192.0.2.1:443 was not refused at once (curl exit status $STATUS)" ;;
esac

printf 'firewall: in force (defaultAction=%s, presets=%s, failureMode=%s, GitHub ranges: %s); record: %s\n' \
  "$(field defaultAction "$RECORD")" "$(field presets "$RECORD")" "$MODE" "$(field githubRanges "$RECORD")" \
  "$RECORD"
