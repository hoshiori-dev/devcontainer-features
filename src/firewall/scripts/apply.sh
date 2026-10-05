#!/bin/sh
# Applies the firewall of the firewall feature: the feature's entrypoint, run as root at every container start,
# before the container's command. It replaces everything an earlier run applied, and reads only root-owned inputs:
# the options install.sh stored in /usr/local/share/firewall/options, /etc/resolv.conf, its own state in
# /var/lib/firewall, and the response of https://api.github.com/meta. In order: the closed table (loopback, replies,
# IPv6 neighbour discovery, DNS to the recorded resolvers); with the github preset and defaultAction deny, the closed
# table plus api.github.com on TCP 443, and the fetch of GitHub's ranges; the full table, in one transaction;
# dnsmasq; /etc/resolv.conf naming dnsmasq. The result goes to the start record /run/firewall/status, which check.sh
# reports. It takes no option from its environment or its arguments.
# POSIX sh, because Alpine images ship no bash.

# Deviation from the layout of shell-style.md (Skeletons), which the feature's design records under Goals, "The check
# ignores its environment": the script first runs itself again with PATH as its whole environment, before `set -eu`,
# the constants, and the functions, so that none of its lines, the sourcing of common.sh included, runs under the
# environment it inherits.
if [ "${1-}" != "--clean" ]; then
  exec /usr/bin/env --ignore-environment PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/sh /usr/local/share/firewall/apply.sh --clean
fi
set -eu
# Every file this script writes is readable by every user and writable by root alone.
umask 022

readonly SHARE_DIR="/usr/local/share/firewall"
readonly OPTIONS_FILE="${SHARE_DIR}/options"
readonly RUN_DIR="/run/firewall"
readonly RECORD_FILE="${RUN_DIR}/status"
readonly RECORD_TMP_FILE="${RUN_DIR}/status.tmp"
readonly RULES_FILE="${RUN_DIR}/rules.nft"
readonly DNSMASQ_CONF_FILE="${RUN_DIR}/dnsmasq.conf"
readonly DNSMASQ_PID_FILE="${RUN_DIR}/dnsmasq.pid"
readonly DNSMASQ_ERROR_FILE="${RUN_DIR}/dnsmasq.err"
readonly META_FILE="${RUN_DIR}/meta.json"
readonly META_HEADERS_FILE="${RUN_DIR}/meta.headers"
readonly STATE_DIR="/var/lib/firewall"
readonly RESOLVERS_FILE="${STATE_DIR}/resolvers"
readonly RESOLV_CONF="/etc/resolv.conf"
# The feature's own nftables table; no other table is read or changed.
readonly TABLE_FAMILY="inet"
readonly TABLE_NAME="firewall"
# Where dnsmasq listens. common.sh defines PROBE_ADDRESS (192.0.2.1), which the rules always refuse.
readonly LOCAL_RESOLVER="127.0.0.1"
readonly META_HOST="api.github.com"
readonly META_URL="https://api.github.com/meta"
readonly META_MAX_BYTES=2097152

# The options, which read_options of common.sh sets from OPTIONS_FILE; none is taken from the environment.
DEFAULTACTION=""
PRESETS=""
ALLOWEDDOMAINS=""
ALLOWEDCIDRS=""
DENIEDDOMAINS=""
DENIEDCIDRS=""
FAILUREMODE=""
FILTERFORWARD=""

# What read_options and validate_options of common.sh set: why a value was rejected, and the validated lists.
reason=""
preset_list=""
preset_domain_list=""
allowed_domain_list=""
allowed_cidr_lines=""
denied_domain_list=""
denied_cidr_lines=""
# What the script was doing, for the record of a start that stops unexpectedly.
step="starting"
# The start time of the container's PID 1, which tells the record of this start from that of an earlier one.
start_time=""
# The first failure found before the closed table is loaded; the start ends with it once that table is in place.
deferred_failure=""
# The recorded resolvers, space-separated, and their IPv4 and IPv6 addresses as the bodies of nft sets.
resolvers=""
resolvers4=""
resolvers6=""
# The addresses one lookup of META_HOST returned: as the bodies of nft sets, and as curl's --resolve list.
meta_addresses4=""
meta_addresses6=""
meta_resolve=""
# The validated ranges of GitHub's meta response (cidr_lines lines), and what the record says about them.
github_cidr_lines=""
github_ranges="not fetched"
# Why load_table could not load a ruleset; empty after a load.
load_error=""

# The feature's library: the option rules this script shares with install.sh, which installed it beside this script.
# Its path exists only inside the image, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "${SHARE_DIR}/common.sh"

log() {
  printf 'firewall: %s\n' "$*"
}

# Waits a fifth of a second. Known failure mode: a sleep that takes no fractional seconds fails, and a full second
# is waited instead.
nap() {
  sleep 0.2 2>/dev/null || sleep 1
}

# Whether the process with the ID $1 exists and is not a zombie. An image without an init process leaves a stopped
# dnsmasq as a zombie, which holds no port.
proc_alive() {
  if [ ! -r "/proc/$1/stat" ]; then return 1; fi
  if ! IFS= read -r proc_alive_stat <"/proc/$1/stat"; then return 1; fi
  # The state is the first field after the command name, which stands in parentheses and may hold spaces.
  case "${proc_alive_stat##*) }" in
    Z*) return 1 ;;
  esac
}

# Prints the addresses of family $1 (4 or 6) among the cidr_lines lines $2 as the body of an nft set: "a, b".
set_body() {
  awk -v family="$1" '$1 == family { sub(/\/[0-9]+$/, "", $3); printf "%s%s", separator, $3; separator = ", " }' <<EOF
$2
EOF
}

# Writes the start record: the result $1 (applied, failed, or not-applied), its reason $2, the time, the start it
# belongs to, the options in effect, the fetched ranges, and the recorded resolvers. The record replaces the earlier
# one in one step, since check.sh may read it at any time.
write_record() {
  write_record_time="$(date --utc +%Y-%m-%dT%H:%M:%SZ)"
  cat >"${RECORD_TMP_FILE}" <<EOF || return
result=$1
reason=${2%%"${NL}"*}
time=${write_record_time}
start=${start_time}
defaultAction=${DEFAULTACTION}
presets=${PRESETS}
allowedDomains=${ALLOWEDDOMAINS}
allowedCidrs=${ALLOWEDCIDRS}
deniedDomains=${DENIEDDOMAINS}
deniedCidrs=${DENIEDCIDRS}
failureMode=${FAILUREMODE}
filterForward=${FILTERFORWARD}
githubRanges=${github_ranges}
resolvers=${resolvers}
EOF
  mv --force "${RECORD_TMP_FILE}" "${RECORD_FILE}"
}

# Replaces the nameserver lines of /etc/resolv.conf with the space-separated addresses $1 and keeps every other
# line. The file is rewritten in place, because Docker bind-mounts it, and only once its new text is complete.
write_nameservers() {
  write_nameservers_text="$(
    awk -v servers="$1" '
      function emit(   i, n) {
        if (!emitted) { n = split(servers, addresses, " "); for (i = 1; i <= n; i++) print "nameserver " addresses[i] }
        emitted = 1
      }
      $1 == "nameserver" { emit(); next }
      { print }
      END { emit() }' "${RESOLV_CONF}"
  )" || return
  printf '%s\n' "${write_nameservers_text}" >"${RESOLV_CONF}"
}

# Prints the nft script that replaces the feature's table in one transaction, for the mode $1: closed (loopback,
# replies, IPv6 neighbour discovery, DNS to the recorded resolvers), pinned (closed plus the looked-up addresses of
# META_HOST on TCP 443), or full (the configured rules).
# Deviation from shell-style.md (Options are data), which the feature's design records under Goals, "Option values
# reach the generated files only in validated form": this script is generated from option values, because only a
# file loads the whole table in one transaction. Of an option, only CIDRs reach it, each as cidr_lines printed it
# again from the numbers it parsed, which cannot carry an nft statement; the other options select fixed text.
ruleset() {
  ruleset_ranges=""
  if [ "$1" = "full" ]; then
    ruleset_allowed="$(
      sort -u <<EOF
${allowed_cidr_lines}
${github_cidr_lines}
EOF
    )"
    # One rule pair per prefix length, longest first: the refusal of that length's denied entries before the
    # acceptance of its allowed ones, so the longest match decides and a tie refuses. The learned sets hold single
    # addresses and join the /32 and /128 pairs.
    ruleset_ranges="$(
      awk '
        $0 == "denied" { denied = 1; next }
        NF == 3 {
          key = $1 " " $2
          if (denied) { if (key in refuse) refuse[key] = refuse[key] ", " $3; else refuse[key] = $3 }
          else if (key in accept) accept[key] = accept[key] ", " $3
          else accept[key] = $3
        }
        END {
          for (family = 4; family <= 6; family += 2) {
            match_word = (family == 4) ? "ip" : "ip6"
            longest = (family == 4) ? 32 : 128
            for (len = longest; len >= 0; len--) {
              key = family " " len
              if (key in refuse) printf "\t\t%s daddr { %s } goto refuse\n", match_word, refuse[key]
              if (len == longest) printf "\t\t%s daddr @denied_learned%d goto refuse\n", match_word, family
              if (key in accept) printf "\t\t%s daddr { %s } accept\n", match_word, accept[key]
              if (len == longest) printf "\t\t%s daddr @allowed_learned%d accept\n", match_word, family
            }
          }
        }' <<EOF
${ruleset_allowed}
denied
${denied_cidr_lines}
EOF
    )"
  fi

  printf 'table %s %s\ndelete table %s %s\n' "${TABLE_FAMILY}" "${TABLE_NAME}" "${TABLE_FAMILY}" "${TABLE_NAME}"
  printf 'table %s %s {\n' "${TABLE_FAMILY}" "${TABLE_NAME}"
  if [ "$1" = "full" ]; then
    printf '\tset %s {\n\t\ttype ipv4_addr\n\t}\n' allowed_learned4 denied_learned4
    printf '\tset %s {\n\t\ttype ipv6_addr\n\t}\n' allowed_learned6 denied_learned6
  fi
  printf '\tchain refuse {\n'
  printf '\t\tmeta l4proto tcp reject with tcp reset\n'
  printf '\t\treject with icmpx type admin-prohibited\n'
  printf '\t}\n'
  ruleset_hooks="output"
  if [ "${FILTERFORWARD}" != "false" ]; then ruleset_hooks="output forward"; fi
  for ruleset_hook in ${ruleset_hooks}; do
    printf '\tchain %s {\n' "${ruleset_hook}"
    printf '\t\ttype filter hook %s priority filter; policy drop;\n' "${ruleset_hook}"
    # Traffic through lo includes Docker's redirection of queries to its embedded resolver, 127.0.0.11.
    if [ "${ruleset_hook}" = "output" ]; then printf '\t\toifname "lo" accept\n'; fi
    printf '\t\tct state established,related accept\n'
    printf '\t\ticmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }'
    printf ' ip6 hoplimit 255 accept\n'
    printf '\t\ticmpv6 type mld2-listener-report ip6 hoplimit 1 accept\n'
    if [ -n "${resolvers4}" ]; then
      printf '\t\tip daddr { %s } meta l4proto { tcp, udp } th dport 53 accept\n' "${resolvers4}"
    fi
    if [ -n "${resolvers6}" ]; then
      printf '\t\tip6 daddr { %s } meta l4proto { tcp, udp } th dport 53 accept\n' "${resolvers6}"
    fi
    printf '\t\tmeta l4proto { tcp, udp } th dport 53 goto refuse\n'
    ruleset_last="goto refuse"
    case "$1" in
      pinned)
        if [ -n "${meta_addresses4}" ]; then
          printf '\t\tip daddr { %s } tcp dport 443 accept\n' "${meta_addresses4}"
        fi
        if [ -n "${meta_addresses6}" ]; then
          printf '\t\tip6 daddr { %s } tcp dport 443 accept\n' "${meta_addresses6}"
        fi
        ;;
      full)
        printf '\t\toifname "docker0" accept\n'
        printf '\t\toifname "br-*" accept\n'
        printf '\t\tip daddr %s goto refuse\n' "${PROBE_ADDRESS}"
        printf '%s\n' "${ruleset_ranges}"
        if [ "${DEFAULTACTION}" = "allow" ]; then ruleset_last="accept"; fi
        ;;
    esac
    printf '\t\t%s\n' "${ruleset_last}"
    printf '\t}\n'
  done
  printf '}\n'
}

# Prints the only configuration dnsmasq reads: the recorded resolvers as its upstream servers, 127.0.0.1 as its only
# address, the user dnsmasq with the group $1, and one nftset line per domain that names the learned sets of that
# domain's verdict. A domain both allowed and denied gets the denied line alone.
# Deviation from shell-style.md (Options are data), which the feature's design records under Goals, "Option values
# reach the generated files only in validated form": this file is generated from option values, because dnsmasq
# takes its domains from a configuration file. Of an option, only domains reach it, each in lower case and after
# every label matched domain_names, which cannot carry a dnsmasq directive; presets select fixed names.
dnsmasq_conf() {
  printf '# Written by %s/apply.sh at every start; dnsmasq reads no other configuration.\n' "${SHARE_DIR}"
  printf '%s\n' no-resolv no-hosts "listen-address=${LOCAL_RESOLVER}" bind-interfaces user=dnsmasq "group=$1" \
    "pid-file=${DNSMASQ_PID_FILE}"
  for dnsmasq_conf_resolver in ${resolvers}; do
    printf 'server=%s\n' "${dnsmasq_conf_resolver}"
  done
  dnsmasq_conf_sets="#${TABLE_FAMILY}#${TABLE_NAME}#"
  dnsmasq_conf_allowed="$(
    sort -u <<EOF
${preset_domain_list}
${allowed_domain_list}
EOF
  )"
  for dnsmasq_conf_domain in ${dnsmasq_conf_allowed}; do
    case "${NL}${denied_domain_list}${NL}" in
      *"${NL}${dnsmasq_conf_domain}${NL}"*) continue ;;
    esac
    printf 'nftset=/%s/4%sallowed_learned4,6%sallowed_learned6\n' "${dnsmasq_conf_domain}" "${dnsmasq_conf_sets}" \
      "${dnsmasq_conf_sets}"
  done
  for dnsmasq_conf_domain in ${denied_domain_list}; do
    printf 'nftset=/%s/4%sdenied_learned4,6%sdenied_learned6\n' "${dnsmasq_conf_domain}" "${dnsmasq_conf_sets}" \
      "${dnsmasq_conf_sets}"
  done
}

# Ends a start at which no rule can be loaded at all, for the reason $1: without NET_ADMIN or without nftables in
# the kernel, outbound traffic stays unrestricted under both failure modes. Records the start as not applied.
end_not_applied() {
  trap - EXIT
  # From here on, a failing command no longer stops the script: the record is attempted and the status stays 0.
  set +e
  log "$1; outbound traffic is unrestricted"
  write_record not-applied "$1"
  exit 0
}

# Keeps the failure $* for the moment the closed table is in place, unless an earlier one is kept already.
defer_failure() {
  if [ -z "${deferred_failure}" ]; then deferred_failure="$*"; fi
}

# Ends a start that cannot apply the rules in full, for the reason $*: with failureMode warn it removes the
# feature's table, otherwise it leaves the closed table in place; it records the start as failed.
# Deviation from shell-style.md (Logging and failure), which the feature's design records under Goals, "The
# entrypoint always exits zero": this script defines no `fail` that exits 1, and this handler has a name of its own.
# The result of a start reaches the developer through the start record and check.sh, never through the status of
# the entrypoint, so a tool that stops at a failing entrypoint still runs the container's command.
end_failed_start() {
  trap - EXIT
  # From here on, a failing command no longer stops the script: every step below is attempted, the record is
  # written last, and the status stays 0.
  set +e
  end_failed_start_reason="$*"
  log "the start failed: ${end_failed_start_reason}"
  stop_dnsmasq
  if [ -n "${resolvers}" ]; then write_nameservers "${resolvers}"; fi
  if [ "${FAILUREMODE}" = "warn" ]; then
    if nft list table "${TABLE_FAMILY}" "${TABLE_NAME}" >/dev/null 2>&1; then
      nft delete table "${TABLE_FAMILY}" "${TABLE_NAME}"
    fi
    log "failureMode warn: the feature's rules are removed, so outbound traffic is unrestricted"
  else
    load_table closed
    if [ -n "${load_error}" ]; then
      log "${load_error}"
    else
      log "failureMode closed: only loopback and the DNS resolvers are reachable"
    fi
  fi
  write_record failed "${end_failed_start_reason}"
  exit 0
}

# Runs when the script stops anywhere it did not end the start itself: Requirement: Failure mode of the feature's
# spec applies to any stop, so the start is a failed one.
handle_exit() {
  end_failed_start "the start-time script stopped unexpectedly while ${step}"
}

# Ends the start when the script does not run as root: it can then load no rule and write no start record, so
# outbound traffic stays unrestricted and check.sh reports the missing record.
require_root() {
  step="checking for root"
  require_root_uid="$(id -u)"
  if [ "${require_root_uid}" = "0" ]; then return 0; fi
  trap - EXIT
  log "not running as root, so no rule can be loaded and no start record written; outbound traffic is unrestricted"
  exit 0
}

# Creates the run and state directories and sets start_time.
prepare_state() {
  step="preparing ${RUN_DIR} and ${STATE_DIR}"
  mkdir --parents "${RUN_DIR}" "${STATE_DIR}"
  IFS= read -r prepare_state_stat </proc/1/stat
  set -f
  # The start time is field 22 of /proc/1/stat, the twentieth after the command name, which stands in parentheses
  # and may hold spaces; check.sh reads it the same way. The fields are split on purpose.
  # shellcheck disable=SC2086
  set -- ${prepare_state_stat##*) }
  set +f
  start_time="${20}"
}

# Stops the dnsmasq an earlier run of this script started, if it still runs, and waits at most 5 seconds for it to
# go, so that its port is free again.
stop_dnsmasq() {
  step="stopping the resolver of an earlier start"
  if [ ! -s "${DNSMASQ_PID_FILE}" ]; then return 0; fi
  IFS= read -r stop_dnsmasq_pid <"${DNSMASQ_PID_FILE}"
  rm -f "${DNSMASQ_PID_FILE}"
  # The pid file outlives a restart of the container, after which its number may belong to another process: only a
  # process named dnsmasq is stopped.
  if [ ! -r "/proc/${stop_dnsmasq_pid}/comm" ]; then return 0; fi
  IFS= read -r stop_dnsmasq_name <"/proc/${stop_dnsmasq_pid}/comm"
  if [ "${stop_dnsmasq_name}" != "dnsmasq" ]; then return 0; fi
  if ! proc_alive "${stop_dnsmasq_pid}"; then return 0; fi
  # A process that ended in between leaves nothing to wait for.
  kill "${stop_dnsmasq_pid}" || return 0
  stop_dnsmasq_naps=0
  while proc_alive "${stop_dnsmasq_pid}" && [ "${stop_dnsmasq_naps}" -lt 25 ]; do
    nap
    stop_dnsmasq_naps=$((stop_dnsmasq_naps + 1))
  done
}

# Sets resolvers, resolvers4, and resolvers6 to the container's own resolvers and writes them back into
# /etc/resolv.conf. The resolvers are recorded in RESOLVERS_FILE the first time, before the feature ever rewrites
# the file, and again whenever Docker has regenerated it.
record_resolvers() {
  step="recording the resolvers of ${RESOLV_CONF}"
  record_resolvers_current="$(awk '$1 == "nameserver" && NF >= 2 { print $2 }' "${RESOLV_CONF}")"
  record_resolvers_current="$(join_lines "${record_resolvers_current}" " ")"
  record_resolvers_recorded=""
  if [ -s "${RESOLVERS_FILE}" ]; then IFS= read -r record_resolvers_recorded <"${RESOLVERS_FILE}"; fi
  # A file that names dnsmasq alone was left by an earlier start of this container: the record holds its resolvers.
  # Any other content is Docker's, and is recorded.
  record_resolvers_found="${record_resolvers_current}"
  if [ "${record_resolvers_current}" = "${LOCAL_RESOLVER}" ] && [ -n "${record_resolvers_recorded}" ]; then
    record_resolvers_found="${record_resolvers_recorded}"
  fi
  if [ -z "${record_resolvers_found}" ]; then
    defer_failure "${RESOLV_CONF} names no nameserver; give the container a DNS server"
    return 0
  fi
  record_resolvers_entries=""
  for record_resolvers_address in ${record_resolvers_found}; do
    if [ "${record_resolvers_address}" = "${LOCAL_RESOLVER}" ]; then
      defer_failure "${RESOLV_CONF} names ${LOCAL_RESOLVER}, where the feature's resolver listens;" \
        "give the container a DNS server at another address"
      return 0
    fi
    record_resolvers_entries="${record_resolvers_entries}${record_resolvers_address}${NL}"
  done
  if ! record_resolvers_lines="$(cidr_lines address nameserver "${record_resolvers_entries}")"; then
    defer_failure "${record_resolvers_lines}"
    return 0
  fi
  if [ "${record_resolvers_found}" != "${record_resolvers_recorded}" ]; then
    printf '%s\n' "${record_resolvers_found}" >"${RESOLVERS_FILE}"
  fi
  resolvers="${record_resolvers_found}"
  resolvers4="$(set_body 4 "${record_resolvers_lines}")"
  resolvers6="$(set_body 6 "${record_resolvers_lines}")"
  write_nameservers "${resolvers}"
}

# Replaces the feature's table with the ruleset of the mode $1 (closed, pinned, or full) in one transaction. Sets
# load_error to the reason when nft refuses the ruleset, and empties it otherwise.
load_table() {
  step="loading the $1 rules"
  load_error=""
  ruleset "$1" >"${RULES_FILE}"
  if ! load_table_output="$(nft --file "${RULES_FILE}" 2>&1)"; then
    load_error="loading the $1 rules failed: ${load_table_output%%"${NL}"*}"
  fi
}

# Looks META_HOST up once through the recorded resolvers, within 5 seconds, and sets meta_addresses4,
# meta_addresses6, and meta_resolve to the addresses it returned; the fetch connects to no other address.
lookup_meta_host() {
  step="looking up ${META_HOST}"
  log "looking up ${META_HOST} through the recorded resolvers (${resolvers})"
  if ! lookup_meta_host_answer="$(timeout 5 getent ahosts "${META_HOST}")"; then lookup_meta_host_answer=""; fi
  # getent prints one line per address and socket type, the address first.
  lookup_meta_host_addresses="$(
    awk 'NF && !($1 in seen) { seen[$1] = 1; print $1 }' <<EOF
${lookup_meta_host_answer}
EOF
  )"
  if [ -z "${lookup_meta_host_addresses}" ]; then
    end_failed_start "the lookup of ${META_HOST} returned no address within 5 seconds;" \
      "check that the container's DNS resolvers (${resolvers}) answer"
  fi
  if ! lookup_meta_host_lines="$(cidr_lines address "address of ${META_HOST}" "${lookup_meta_host_addresses}")"; then
    end_failed_start "${lookup_meta_host_lines}"
  fi
  meta_addresses4="$(set_body 4 "${lookup_meta_host_lines}")"
  meta_addresses6="$(set_body 6 "${lookup_meta_host_lines}")"
  # curl takes the addresses of one host as a comma-separated list, an IPv6 address in brackets.
  meta_resolve="$(
    awk '
      $1 == 4 { sub(/\/32$/, "", $3); printf "%s%s", separator, $3; separator = "," }
      $1 == 6 { sub(/\/128$/, "", $3); printf "%s[%s]", separator, $3; separator = "," }' <<EOF
${lookup_meta_host_lines}
EOF
  )"
}

# Fetches META_URL to META_FILE over HTTPS, relying on TLS alone, since GitHub publishes no checksum or signature
# for it: from the looked-up addresses only, without following a redirect, at most 20 seconds and 2 MiB per attempt,
# and at most two attempts.
fetch_meta() {
  step="fetching ${META_URL}"
  log "fetching ${META_URL} from ${meta_resolve} to ${META_FILE}"
  for fetch_meta_attempt in 1 2; do
    rm -f "${META_FILE}" "${META_HEADERS_FILE}"
    if fetch_meta_error="$(
      curl --disable --silent --show-error --proto '=https' --max-time 20 --max-filesize "${META_MAX_BYTES}" \
        --resolve "${META_HOST}:443:${meta_resolve}" --dump-header "${META_HEADERS_FILE}" --output "${META_FILE}" \
        "${META_URL}" 2>&1
    )"; then
      fetch_meta_status=0
    else
      fetch_meta_status=$?
    fi
    case "${fetch_meta_status}" in
      # Known failure mode, a connection error or a timeout: curl could not connect (7), ran out of time (28),
      # failed the TLS handshake (35), got an empty reply (52), or failed while sending (55) or receiving (56).
      # The fetch is tried once more. No other status is retried, an HTTP error status least of all.
      7 | 28 | 35 | 52 | 55 | 56)
        if [ "${fetch_meta_attempt}" = "1" ]; then
          log "fetching ${META_URL} failed (${fetch_meta_error}); trying once more"
        fi
        ;;
      *) break ;;
    esac
  done
  fetch_meta_fix="check that the container reaches ${META_HOST} on port 443"
  case "${fetch_meta_status}" in
    0) ;;
    7 | 28 | 35 | 52 | 55 | 56)
      end_failed_start "fetching ${META_URL} failed twice: ${fetch_meta_error}; ${fetch_meta_fix}"
      ;;
    # curl refuses a response that announces more than --max-filesize.
    63) end_failed_start "the response of ${META_URL} is larger than 2 MiB" ;;
    *) end_failed_start "fetching ${META_URL} failed: ${fetch_meta_error}; ${fetch_meta_fix}" ;;
  esac
  # curl before 8.4.0, as on debian:12, applies --max-filesize only to a response that announces its length.
  fetch_meta_size="$(wc -c <"${META_FILE}")"
  if [ "${fetch_meta_size}" -gt "${META_MAX_BYTES}" ]; then
    end_failed_start "the response of ${META_URL} is larger than 2 MiB"
  fi
  # The last status line counts, and the rate limit's header, whatever the letter case of its name.
  fetch_meta_http="$(
    awk 'toupper(substr($1, 1, 5)) == "HTTP/" { code = $2 } END { print code }' "${META_HEADERS_FILE}"
  )"
  if [ "${fetch_meta_http}" = "200" ]; then return 0; fi
  fetch_meta_remaining="$(
    awk 'tolower($1) == "x-ratelimit-remaining:" { remaining = $2 + 0 } END { print remaining }' "${META_HEADERS_FILE}"
  )"
  case "${fetch_meta_http}:${fetch_meta_remaining}" in
    403:0 | 429:0)
      end_failed_start "the rate limit of GitHub's API is exhausted (HTTP ${fetch_meta_http} from ${META_URL});" \
        "wait until the limit resets"
      ;;
  esac
  end_failed_start "${META_URL} answered HTTP ${fetch_meta_http:-without a status}"
}

# Starts dnsmasq from its own configuration and waits at most 5 seconds until it listens. dnsmasq binds its address
# itself, so a port another process holds ends the start here, before /etc/resolv.conf names dnsmasq.
start_dnsmasq() {
  step="starting the resolver"
  if ! start_dnsmasq_group="$(id -gn dnsmasq 2>/dev/null)"; then
    end_failed_start "the image has no dnsmasq user, which the resolver runs as; rebuild the container image"
  fi
  dnsmasq_conf "${start_dnsmasq_group}" >"${DNSMASQ_CONF_FILE}"
  rm -f "${DNSMASQ_PID_FILE}"
  if ! timeout 5 dnsmasq --conf-file="${DNSMASQ_CONF_FILE}" </dev/null >"${DNSMASQ_ERROR_FILE}" 2>&1; then
    # dnsmasq starts its message with an empty line.
    start_dnsmasq_error="$(awk 'NF { print; exit }' "${DNSMASQ_ERROR_FILE}")"
    end_failed_start "the resolver (dnsmasq) could not start: ${start_dnsmasq_error};" \
      "no other process may listen on ${LOCAL_RESOLVER} port 53"
  fi
  start_dnsmasq_naps=0
  while [ "${start_dnsmasq_naps}" -lt 25 ]; do
    start_dnsmasq_pid=""
    if [ -s "${DNSMASQ_PID_FILE}" ]; then IFS= read -r start_dnsmasq_pid <"${DNSMASQ_PID_FILE}"; fi
    # A UDP socket bound to 127.0.0.1:53, as /proc/net/udp writes it on a little-endian machine (amd64, arm64).
    if [ -n "${start_dnsmasq_pid}" ] && proc_alive "${start_dnsmasq_pid}" \
      && awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp; then
      # dnsmasq gives its pid file to the user it runs as. The next start reads only files that root wrote, so root
      # writes the file anew.
      rm -f "${DNSMASQ_PID_FILE}"
      printf '%s\n' "${start_dnsmasq_pid}" >"${DNSMASQ_PID_FILE}"
      return 0
    fi
    nap
    start_dnsmasq_naps=$((start_dnsmasq_naps + 1))
  done
  end_failed_start "the resolver (dnsmasq) did not listen on ${LOCAL_RESOLVER} port 53 within 5 seconds"
}

main() {
  trap handle_exit EXIT
  require_root
  prepare_state
  if ! read_options "${OPTIONS_FILE}"; then
    defer_failure "${reason}"
  elif ! validate_options; then
    defer_failure "the options in ${OPTIONS_FILE} are not valid: ${reason}"
  fi
  stop_dnsmasq
  record_resolvers

  # The closed table is the first ruleset of every start, whatever else is wrong with it.
  load_table closed
  if [ -n "${load_error}" ]; then end_not_applied "${load_error}"; fi
  if [ -n "${deferred_failure}" ]; then end_failed_start "${deferred_failure}"; fi

  # GitHub's ranges only allow, so they are fetched only where the github preset is selected and unlisted traffic is
  # refused.
  case "${DEFAULTACTION}:${NL}${preset_list}${NL}" in
    deny:*"${NL}github${NL}"*)
      lookup_meta_host
      load_table pinned
      if [ -n "${load_error}" ]; then end_failed_start "${load_error}"; fi
      fetch_meta
      step="validating the ranges of ${META_URL}"
      if ! github_cidr_lines="$(meta_ranges "${META_FILE}")"; then end_failed_start "${github_cidr_lines}"; fi
      main_count="$(
        awk 'NF { count++ } END { print count + 0 }' <<EOF
${github_cidr_lines}
EOF
      )"
      github_ranges="${main_count} ranges from ${META_URL}"
      ;;
  esac

  # dnsmasq starts only after this load, which creates the learned sets anew, and /etc/resolv.conf names dnsmasq
  # only once it listens.
  load_table full
  if [ -n "${load_error}" ]; then end_failed_start "${load_error}"; fi
  start_dnsmasq
  step="pointing ${RESOLV_CONF} at the resolver"
  write_nameservers "${LOCAL_RESOLVER}"

  trap - EXIT
  write_record applied ""
  log "applied (defaultAction=${DEFAULTACTION}, presets=${PRESETS}, GitHub ranges: ${github_ranges})"
}

main "$@"
