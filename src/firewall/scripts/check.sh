#!/bin/sh
# Checks that the firewall of the current container start is in force: the feature's postStartCommand, run without
# privilege. It waits at most 90 seconds for the start record that apply.sh writes to /run/firewall/status, takes a
# record of an earlier start for a missing one, and connects to 192.0.2.1 on port 443, which the rules refuse
# whatever the options say: only a connection refused at once proves them in force, and no host on the Internet is
# contacted. When the firewall is not in force it says why, as an error with status 1 or, with failureMode warn, as a
# warning with status 0. It takes no options, and reads only the start record and the failure mode in
# /usr/local/share/firewall/options.
# POSIX sh, because Alpine images ship no bash.

# Deviation from the layout of shell-style.md (Skeletons), which the feature's design records under Goals, "The check
# ignores its environment": the script first runs itself again with PATH as its whole environment, before `set -eu`,
# the constants, and the functions, so that none of its lines runs under the environment it inherits. It also calls
# every tool by its absolute path, so the remote user's PATH, ENV, or BASH_ENV cannot change its result.
if [ "${1-}" != "--clean" ]; then
  exec /usr/bin/env --ignore-environment PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/sh /usr/local/share/firewall/check.sh --clean
fi
set -eu

readonly RECORD_FILE="/run/firewall/status"
readonly OPTIONS_FILE="/usr/local/share/firewall/options"
# The probe: plain HTTP to port 443 of TEST-NET-1 (RFC 5737), where only the firewall's TCP reset answers.
readonly PROBE_URL="http://192.0.2.1:443/"
readonly WAIT_SECONDS=90

# The failure mode the image was built with: closed or warn.
failure_mode="closed"

log() {
  printf 'firewall: %s\n' "$*"
}

fail() {
  printf 'firewall: error: %s\n' "$*" >&2
  exit 1
}

# Reports that the firewall is not in force, for the reason $*, and ends the check: with failureMode warn as a
# warning with status 0, otherwise as an error with status 1.
not_in_force() {
  if [ "${failure_mode}" = "warn" ]; then
    printf 'firewall: warning: %s\n' "the firewall is not in force: $*" >&2
    exit 0
  fi
  fail "the firewall is not in force: $*"
}

# Prints the value of the first "$1=value" line of the file $2, and nothing when the file or the line is missing.
field() {
  if [ ! -r "$2" ]; then return 0; fi
  while IFS= read -r field_line; do
    case "${field_line}" in
      "$1="*)
        printf '%s\n' "${field_line#*=}"
        return 0
        ;;
    esac
  done <"$2"
}

# Sets failure_mode from the options install.sh stored.
read_failure_mode() {
  failure_mode="$(field failureMode "${OPTIONS_FILE}")"
  # A mode that cannot be read counts as closed, so a broken install fails the check and never only warns.
  if [ "${failure_mode}" != "warn" ]; then failure_mode="closed"; fi
}

# Waits until the start record belongs to the current start: apply.sh may still be running, and a record an earlier
# start left counts as missing.
wait_for_record() {
  if ! IFS= read -r wait_for_record_stat </proc/1/stat; then
    not_in_force "cannot read /proc/1/stat, which tells the current start from an earlier one"
  fi
  set -f
  # The start time of PID 1 is field 22 of /proc/1/stat, the twentieth after the command name, which stands in
  # parentheses and may hold spaces; apply.sh records it the same way. The fields are split on purpose.
  # shellcheck disable=SC2086
  set -- ${wait_for_record_stat##*) }
  set +f
  wait_for_record_start="${20-}"
  wait_for_record_waited=0
  while :; do
    wait_for_record_recorded="$(field start "${RECORD_FILE}")"
    if [ -n "${wait_for_record_start}" ] && [ "${wait_for_record_recorded}" = "${wait_for_record_start}" ]; then
      return 0
    fi
    if [ "${wait_for_record_waited}" -ge "${WAIT_SECONDS}" ]; then
      not_in_force "${RECORD_FILE} holds no record of the current start after ${WAIT_SECONDS} seconds," \
        "so the start was not applied; run the container's entrypoint as root, and see the container log"
    fi
    /bin/sleep 1
    wait_for_record_waited=$((wait_for_record_waited + 1))
  done
}

# Ends the check unless the record says that the start applied the rules.
check_result() {
  check_result_result="$(field result "${RECORD_FILE}")"
  check_result_reason="$(field reason "${RECORD_FILE}")"
  case "${check_result_result}" in
    applied) ;;
    failed)
      not_in_force "the start failed: ${check_result_reason}; restart the container once that is resolved"
      ;;
    not-applied)
      not_in_force "no rule could be loaded: ${check_result_reason};" \
        "run the container with the NET_ADMIN capability on a kernel with nftables"
      ;;
    *) not_in_force "${RECORD_FILE} names no known result (\"${check_result_result}\")" ;;
  esac
}

# Ends the check unless a connection to the probe address is refused within 3 seconds. A timeout or an unreachable
# network means that the rules are not in place: without them nothing answers for this address.
probe() {
  if probe_output="$(
    /usr/bin/curl --disable --verbose --silent --show-error --connect-timeout 3 --max-time 3 --output /dev/null \
      "${PROBE_URL}" 2>&1
  )"; then
    probe_status=0
  else
    probe_status=$?
  fi
  case "${probe_status}:${probe_output}" in
    7:*"Connection refused"*) ;;
    *)
      not_in_force "the probe to ${PROBE_URL} was not refused at once (curl exit status ${probe_status});" \
        "restart the container to apply the rules again"
      ;;
  esac
}

# Prints the one-line summary of a firewall in force.
report() {
  report_action="$(field defaultAction "${RECORD_FILE}")"
  report_presets="$(field presets "${RECORD_FILE}")"
  report_ranges="$(field githubRanges "${RECORD_FILE}")"
  log "in force (defaultAction=${report_action}, presets=${report_presets}, failureMode=${failure_mode}," \
    "GitHub ranges: ${report_ranges}); record: ${RECORD_FILE}"
}

main() {
  read_failure_mode
  wait_for_record
  check_result
  probe
  report
}

main "$@"
