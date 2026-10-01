#!/bin/sh
# Start-time firewall of the firewall feature. The feature's entrypoint runs it as root at every
# container start, before the container's command; it replaces everything an earlier run applied.
# It reads only root-owned inputs: the options install.sh stored in /usr/local/share/firewall/options,
# /etc/resolv.conf, its state directory /var/lib/firewall, and the GitHub meta response. Order: the
# closed table (loopback, ICMPv6 neighbour discovery, DNS to the recorded resolvers), then, with the
# github preset and defaultAction deny, the closed table plus api.github.com on TCP 443 and the fetch
# of the GitHub ranges, then the full table in one transaction, then dnsmasq, then /etc/resolv.conf
# naming dnsmasq. The result goes to the start record /run/firewall/status, which check.sh reports;
# the script itself always exits zero, so it never stops the container's command.
# POSIX sh: Alpine ships no bash.

# Ignore the inherited environment: a fixed PATH, nothing else.
if [ "${1-}" != --clean ]; then
  exec /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/sh /usr/local/share/firewall/apply.sh --clean
fi
set -eu
umask 022

SHARE=/usr/local/share/firewall
RUN=/run/firewall
STATE=/var/lib/firewall
PROBE=192.0.2.1
META_HOST=api.github.com
META_URL=https://api.github.com/meta
META_MAX_BYTES=2097152

# shellcheck source=/dev/null
. "$SHARE/common.sh"

log() {
  printf 'firewall: %s\n' "$*" >&2
}

# nap: a short wait for the polling loops.
nap() {
  sleep 0.2 2>/dev/null || sleep 1
}

# pid1_start: the start time of the container's PID 1 (field 22 of /proc/1/stat), which tells the
# current start from an earlier one; check.sh reads it the same way.
pid1_start() {
  IFS= read -r fw_stat </proc/1/stat || return 1
  set -f
  # shellcheck disable=SC2086 # split the fields after the command name
  set -- ${fw_stat##*) }
  set +f
  [ $# -ge 20 ] || return 1
  shift 19
  printf '%s\n' "$1"
}

# proc_alive PID: the process exists and is not a zombie.
proc_alive() {
  [ -r "/proc/$1/stat" ] || return 1
  IFS= read -r fw_pstat <"/proc/$1/stat" || return 1
  set -f
  # shellcheck disable=SC2086
  set -- ${fw_pstat##*) }
  set +f
  [ "${1-}" != Z ]
}

# record RESULT REASON: writes the start record atomically, readable by every user.
record() {
  fw_tmp="$RUN/status.tmp"
  {
    printf 'result=%s\n' "$1"
    printf 'reason=%s\n' "$(printf '%s' "$2" | tr '\n\t' '  ')"
    printf 'time=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'start=%s\n' "$START"
    printf 'defaultAction=%s\n' "$OPT_DEFAULT_ACTION"
    printf 'presets=%s\n' "$OPT_PRESETS"
    printf 'allowedDomains=%s\n' "$OPT_ALLOWED_DOMAINS"
    printf 'allowedCidrs=%s\n' "$OPT_ALLOWED_CIDRS"
    printf 'deniedDomains=%s\n' "$OPT_DENIED_DOMAINS"
    printf 'deniedCidrs=%s\n' "$OPT_DENIED_CIDRS"
    printf 'failureMode=%s\n' "$OPT_FAILURE_MODE"
    printf 'filterForward=%s\n' "$OPT_FILTER_FORWARD"
    printf 'githubRanges=%s\n' "$GITHUB_RANGES"
    printf 'resolvers=%s\n' "$RESOLVERS"
  } >"$fw_tmp"
  chmod 0644 "$fw_tmp"
  mv -f "$fw_tmp" "$RUN/status"
  RECORDED=1
}

# stop_dnsmasq: stops the dnsmasq an earlier run of this script started, if it still runs.
stop_dnsmasq() {
  [ -r "$RUN/dnsmasq.pid" ] || return 0
  fw_pid=
  IFS= read -r fw_pid <"$RUN/dnsmasq.pid" || true
  rm -f "$RUN/dnsmasq.pid"
  case $fw_pid in '' | *[!0-9]*) return 0 ;; esac
  proc_alive "$fw_pid" || return 0
  fw_comm=
  IFS= read -r fw_comm <"/proc/$fw_pid/comm" || return 0
  [ "$fw_comm" = dnsmasq ] || return 0
  kill "$fw_pid" 2>/dev/null || return 0
  fw_i=0
  while proc_alive "$fw_pid" && [ $fw_i -lt 25 ]; do
    nap
    fw_i=$((fw_i + 1))
  done
  if proc_alive "$fw_pid"; then kill -9 "$fw_pid" 2>/dev/null || true; fi
}

# nameservers: the nameserver addresses of /etc/resolv.conf, space-separated, in order.
nameservers() {
  awk '$1 == "nameserver" && NF >= 2 { printf "%s%s", sep, $2; sep = " " } END { print "" }' /etc/resolv.conf
}

# write_nameservers ADDRESSES: replaces the nameserver lines of /etc/resolv.conf with ADDRESSES and
# keeps every other line. The file is rewritten in place: Docker bind-mounts it.
write_nameservers() {
  fw_tmp="$RUN/resolv.conf.tmp"
  awk -v ns="$1" '
    function emit(  i, n) {
      if (!done) { n = split(ns, addrs, " "); for (i = 1; i <= n; i++) print "nameserver " addrs[i] }
      done = 1
    }
    $1 == "nameserver" { emit(); next }
    { print }
    END { emit() }' /etc/resolv.conf >"$fw_tmp" || return 1
  cat "$fw_tmp" >/etc/resolv.conf || return 1
  rm -f "$fw_tmp"
}

# addresses FAMILY LINES: the single addresses of family 4 or 6 among fw_check_cidrs LINES, as an
# nft set body ("a, b").
addresses() {
  printf '%s\n' "$2" | awk -v f="$1" '$1 == f { sub(/\/[0-9]+$/, "", $3); print $3 }' | fw_join | sed 's/,/, /g'
}

# setup_resolvers: sets RESOLVERS, RES4, and RES6 from the recorded resolvers, recording the
# nameservers of /etc/resolv.conf first when none are recorded or Docker has regenerated the file.
setup_resolvers() {
  fw_current=$(nameservers) || fw_current=
  fw_recorded=
  if [ -r "$STATE/resolvers" ]; then IFS= read -r fw_recorded <"$STATE/resolvers" || true; fi
  if [ -n "$fw_recorded" ] && { [ "$fw_current" = 127.0.0.1 ] || [ "$fw_current" = "$fw_recorded" ]; }; then
    fw_resolvers=$fw_recorded
  else
    fw_resolvers=$fw_current
    if [ -z "$fw_resolvers" ]; then
      FW_ERROR="/etc/resolv.conf names no nameserver"
      return 1
    fi
    case " $fw_resolvers " in
      *" 127.0.0.1 "*)
        FW_ERROR="/etc/resolv.conf names 127.0.0.1, where the feature's resolver listens, and no resolvers are recorded"
        return 1
        ;;
    esac
  fi
  case $fw_resolvers in
    */*)
      FW_ERROR="the nameservers \"$fw_resolvers\" are not addresses"
      return 1
      ;;
  esac
  # shellcheck disable=SC2086 # one address per line
  if ! fw_checked FW_RESOLVER_LINES "$(printf '%s,' $fw_resolvers)" fw_check_cidrs denied nameserver; then
    return 1
  fi
  if [ "$fw_resolvers" != "$fw_recorded" ]; then
    printf '%s\n' "$fw_resolvers" >"$STATE/resolvers.tmp"
    chmod 0644 "$STATE/resolvers.tmp"
    mv -f "$STATE/resolvers.tmp" "$STATE/resolvers"
  fi
  RESOLVERS=$fw_resolvers
  RES4=$(addresses 4 "$FW_RESOLVER_LINES")
  RES6=$(addresses 6 "$FW_RESOLVER_LINES")
}

# prefix_rules: one rule pair per prefix length, longest first, from "<allow|deny> <family> <length>
# <cidr>" lines: the denied entries' refusal before the allowed entries' acceptance, so the longest
# match decides and a tie refuses. The learned sets hold single addresses and join the /32 and /128 pairs.
prefix_rules() {
  awk '
    NF == 4 {
      k = $2 " " $3
      if ($1 == "deny") { if (k in d) d[k] = d[k] ", " $4; else d[k] = $4 }
      else if (k in a) a[k] = a[k] ", " $4
      else a[k] = $4
    }
    END {
      for (f = 4; f <= 6; f += 2) {
        kw = (f == 4) ? "ip" : "ip6"
        max = (f == 4) ? 32 : 128
        for (len = max; len >= 0; len--) {
          k = f " " len
          if (k in d) printf "\t\t%s daddr { %s } goto refuse\n", kw, d[k]
          if (len == max) printf "\t\t%s daddr @denied_learned%d goto refuse\n", kw, f
          if (k in a) printf "\t\t%s daddr { %s } accept\n", kw, a[k]
          if (len == max) printf "\t\t%s daddr @allowed_learned%d accept\n", kw, f
        }
      }
    }'
}

# chain_rules MODE: the rules shared by the output and forward chains. MODE is closed (loopback,
# replies, ICMPv6 neighbour discovery, DNS to the recorded resolvers), pinned (closed plus
# api.github.com on TCP 443), or full (the configured rules).
chain_rules() {
  printf '\t\tct state established,related accept\n'
  printf '\t\ticmpv6 type { nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }'
  printf ' ip6 hoplimit 255 accept\n'
  printf '\t\ticmpv6 type mld2-listener-report ip6 hoplimit 1 accept\n'
  if [ -n "$RES4" ]; then printf '\t\tip daddr { %s } meta l4proto { tcp, udp } th dport 53 accept\n' "$RES4"; fi
  if [ -n "$RES6" ]; then printf '\t\tip6 daddr { %s } meta l4proto { tcp, udp } th dport 53 accept\n' "$RES6"; fi
  printf '\t\tmeta l4proto { tcp, udp } th dport 53 goto refuse\n'
  case $1 in
    pinned)
      if [ -n "$PIN4" ]; then printf '\t\tip daddr { %s } tcp dport 443 accept\n' "$PIN4"; fi
      if [ -n "$PIN6" ]; then printf '\t\tip6 daddr { %s } tcp dport 443 accept\n' "$PIN6"; fi
      ;;
    full)
      printf '\t\toifname "docker0" accept\n'
      printf '\t\toifname "br-*" accept\n'
      printf '\t\tip daddr %s goto refuse\n' "$PROBE"
      printf '%s\n' "$ENTRIES" | prefix_rules
      if [ "$OPT_DEFAULT_ACTION" = allow ]; then
        printf '\t\taccept\n'
        return 0
      fi
      ;;
  esac
  printf '\t\tgoto refuse\n'
}

# ruleset MODE: the nft script that replaces the feature's table in one transaction.
ruleset() {
  printf 'table inet firewall\ndelete table inet firewall\ntable inet firewall {\n'
  if [ "$1" = full ]; then
    for fw_set in allowed_learned4 denied_learned4; do printf '\tset %s {\n\t\ttype ipv4_addr\n\t}\n' "$fw_set"; done
    for fw_set in allowed_learned6 denied_learned6; do printf '\tset %s {\n\t\ttype ipv6_addr\n\t}\n' "$fw_set"; done
  fi
  printf '\tchain refuse {\n'
  printf '\t\tmeta l4proto tcp reject with tcp reset\n'
  printf '\t\treject with icmpx type admin-prohibited\n'
  printf '\t}\n'
  printf '\tchain output {\n'
  printf '\t\ttype filter hook output priority filter; policy drop;\n'
  printf '\t\toifname "lo" accept\n'
  chain_rules "$1"
  printf '\t}\n'
  if [ "$OPT_FILTER_FORWARD" != false ]; then
    printf '\tchain forward {\n'
    printf '\t\ttype filter hook forward priority filter; policy drop;\n'
    chain_rules "$1"
    printf '\t}\n'
  fi
  printf '}\n'
}

# load MODE: loads the ruleset of MODE; on failure sets FW_ERROR.
load() {
  ruleset "$1" >"$RUN/rules.nft"
  if ! fw_err=$(nft -f "$RUN/rules.nft" 2>&1); then
    FW_ERROR="loading the $1 rules failed: $(printf '%s\n' "$fw_err" | sed '/^$/d' | head -n 1)"
    return 1
  fi
}

# lookup_meta_host: one lookup of api.github.com through the recorded resolvers, bounded at 5
# seconds; sets PIN4, PIN6 (for the pinned table) and PIN_RESOLVE (for curl --resolve).
lookup_meta_host() {
  fw_addrs=$(timeout 5 getent ahosts "$META_HOST" 2>/dev/null | awk '{ print $1 }' | sort -u) || fw_addrs=
  if [ -z "$fw_addrs" ]; then
    FW_ERROR="the lookup of $META_HOST returned no address within 5 seconds"
    return 1
  fi
  fw_checked FW_PIN_LINES "$(printf '%s\n' "$fw_addrs" | fw_join)" fw_check_cidrs address "address of $META_HOST" \
    || return 1
  PIN4=$(addresses 4 "$FW_PIN_LINES")
  PIN6=$(addresses 6 "$FW_PIN_LINES")
  PIN_RESOLVE=$(printf '%s\n' "$FW_PIN_LINES" | awk '
    $1 == 4 { sub(/\/32$/, "", $3); print $3 }
    $1 == 6 { sub(/\/128$/, "", $3); print "[" $3 "]" }' | fw_join)
}

# fetch_meta: fetches the GitHub ranges over HTTPS, pinned to the looked-up addresses, at most 20
# seconds and 2 MiB per attempt, retried once only after a connection error or a timeout; sets
# GITHUB_LINES and GITHUB_RANGES, or FW_ERROR.
fetch_meta() {
  fw_try=1
  while :; do
    rm -f "$RUN/meta.json" "$RUN/meta.headers" "$RUN/meta.err" "$RUN/meta.rc"
    {
      fw_rc=0
      curl -q -sS --proto =https --max-time 20 --max-filesize "$META_MAX_BYTES" \
        --resolve "$META_HOST:443:$PIN_RESOLVE" -D "$RUN/meta.headers" -o - "$META_URL" 2>"$RUN/meta.err" \
        || fw_rc=$?
      echo "$fw_rc" >"$RUN/meta.rc"
    } | head -c $((META_MAX_BYTES + 1)) >"$RUN/meta.json"
    fw_rc=
    IFS= read -r fw_rc <"$RUN/meta.rc" || true
    fw_curl_error=$(sed '/^$/d' "$RUN/meta.err" | tail -n 1)
    fw_size=$(wc -c <"$RUN/meta.json" | tr -d ' ')
    if [ "$fw_size" -gt "$META_MAX_BYTES" ]; then
      FW_ERROR="the response of $META_URL is larger than 2 MiB"
      return 1
    fi
    case $fw_rc in
      0) break ;;
      7 | 28 | 35 | 52 | 55 | 56)
        if [ $fw_try -lt 2 ]; then
          log "fetching $META_URL failed ($fw_curl_error); retrying once"
          fw_try=2
          continue
        fi
        FW_ERROR="fetching $META_URL failed twice: $fw_curl_error"
        return 1
        ;;
      63)
        FW_ERROR="the response of $META_URL is larger than 2 MiB"
        return 1
        ;;
      *)
        FW_ERROR="fetching $META_URL failed: ${fw_curl_error:-curl exit status $fw_rc}"
        return 1
        ;;
    esac
  done
  fw_status=$(awk 'toupper(substr($1, 1, 5)) == "HTTP/" { code = $2 } END { print code }' "$RUN/meta.headers")
  if [ "$fw_status" != 200 ]; then
    if awk 'tolower($1) == "x-ratelimit-remaining:" && $2 + 0 == 0 { found = 1 } END { exit !found }' \
      "$RUN/meta.headers" && { [ "$fw_status" = 403 ] || [ "$fw_status" = 429 ]; }; then
      FW_ERROR="GitHub's API rate limit is exhausted (HTTP $fw_status from $META_URL);"
      FW_ERROR="$FW_ERROR a start after the limit resets fetches again"
    else
      FW_ERROR="$META_URL answered HTTP ${fw_status:-without a status}"
    fi
    return 1
  fi
  if ! GITHUB_LINES=$(fw_meta_ranges "$RUN/meta.json"); then
    FW_ERROR=$(printf '%s\n' "$GITHUB_LINES" | tail -n 1)
    GITHUB_LINES=
    return 1
  fi
  GITHUB_RANGES="$(printf '%s\n' "$GITHUB_LINES" | awk 'NF' | wc -l | tr -d ' ') ranges from $META_URL"
}

# dnsmasq_conf GROUP: the resolver's only configuration: the recorded resolvers upstream, 127.0.0.1
# only, and one nftset line per domain naming its own verdict's learned sets; a domain both allowed
# and denied gets only the denied line.
dnsmasq_conf() {
  printf '# Written by %s/apply.sh at every start; dnsmasq reads no other configuration.\n' "$SHARE"
  printf '%s\n' no-resolv no-hosts listen-address=127.0.0.1 bind-interfaces user=dnsmasq "group=$1" \
    "pid-file=$RUN/dnsmasq.pid"
  for fw_r in $RESOLVERS; do printf 'server=%s\n' "$fw_r"; done
  {
    for fw_p in $FW_PRESETS; do fw_preset_domains "$fw_p"; done
    printf '%s\n' "$FW_ALLOWED_DOMAINS"
  } | awk -v denied="$(printf '%s\n' "$FW_DENIED_DOMAINS" | fw_join)" '
    BEGIN { n = split(denied, d, ","); for (i = 1; i <= n; i++) skip[d[i]] = 1 }
    NF && !($0 in skip) && !($0 in seen) {
      seen[$0] = 1
      printf "nftset=/%s/4#inet#firewall#allowed_learned4,6#inet#firewall#allowed_learned6\n", $0
    }'
  printf '%s\n' "$FW_DENIED_DOMAINS" | awk 'NF {
    printf "nftset=/%s/4#inet#firewall#denied_learned4,6#inet#firewall#denied_learned6\n", $0
  }'
}

# dns_listening: a UDP socket is bound to 127.0.0.1:53 (little-endian hex, as on amd64 and arm64).
dns_listening() {
  awk '$2 == "0100007F:0035" { found = 1 } END { exit !found }' /proc/net/udp
}

# start_dnsmasq: starts the resolver and waits at most 5 seconds for it to listen.
start_dnsmasq() {
  if ! fw_group=$(id -gn dnsmasq 2>/dev/null); then
    FW_ERROR="the dnsmasq user is missing"
    return 1
  fi
  dnsmasq_conf "$fw_group" >"$RUN/dnsmasq.conf.tmp"
  chmod 0644 "$RUN/dnsmasq.conf.tmp"
  mv -f "$RUN/dnsmasq.conf.tmp" "$RUN/dnsmasq.conf"
  rm -f "$RUN/dnsmasq.pid"
  if ! timeout 5 dnsmasq --conf-file="$RUN/dnsmasq.conf" </dev/null >"$RUN/dnsmasq.err" 2>&1; then
    FW_ERROR="the resolver could not start: $(sed '/^$/d' "$RUN/dnsmasq.err" | head -n 1)"
    return 1
  fi
  fw_i=0
  while [ $fw_i -lt 25 ]; do
    fw_pid=
    if [ -s "$RUN/dnsmasq.pid" ]; then IFS= read -r fw_pid <"$RUN/dnsmasq.pid" || true; fi
    if [ -n "$fw_pid" ] && proc_alive "$fw_pid" && dns_listening; then return 0; fi
    nap
    fw_i=$((fw_i + 1))
  done
  FW_ERROR="the resolver did not listen on 127.0.0.1:53 within 5 seconds"
  return 1
}

# fail REASON: handles a failed start by failureMode and records it; exits.
fail() {
  trap - EXIT
  log "the start failed: $1"
  stop_dnsmasq || true
  if [ "$RESOLVERS_OK" = 1 ]; then write_nameservers "$RESOLVERS" || log "restoring /etc/resolv.conf failed"; fi
  if [ "$OPT_FAILURE_MODE" = warn ]; then
    nft delete table inet firewall 2>/dev/null || true
    log "failureMode warn: the feature's rules are removed, outbound traffic is unrestricted"
  elif load closed; then
    log "failureMode closed: only loopback and the DNS resolvers are reachable"
  else
    log "$FW_ERROR"
  fi
  record failed "$1"
  exit 0
}

# on_exit: a command failed where the script did not expect it; the start is a failure.
on_exit() {
  [ "$RECORDED" = 1 ] || fail "the start-time script stopped unexpectedly while $STEP"
}

RECORDED=0
RESOLVERS_OK=0
RESOLVERS=
RES4=
RES6=
PIN4=
PIN6=
PIN_RESOLVE=
ENTRIES=
GITHUB_LINES=
GITHUB_RANGES="not fetched"
FW_PRESETS=
FW_ALLOWED_DOMAINS=
FW_ALLOWED_CIDRS=
FW_DENIED_DOMAINS=
FW_DENIED_CIDRS=

if [ "$(id -u)" != 0 ]; then
  log "not running as root, so no rule can be loaded; outbound traffic is unrestricted"
  exit 0
fi
mkdir -p "$RUN" "$STATE"
chmod 0755 "$RUN" "$STATE"
START=$(pid1_start) || START=unknown

STEP="reading the options"
OPTIONS_ERROR=
if ! { fw_read_options "$SHARE/options" && fw_validate_options; }; then
  OPTIONS_ERROR="invalid configuration in $SHARE/options: $FW_ERROR"
fi
trap on_exit EXIT

STEP="stopping the resolver of an earlier run"
stop_dnsmasq

STEP="recording the resolvers"
RESOLVER_ERROR=
if setup_resolvers; then
  RESOLVERS_OK=1
  write_nameservers "$RESOLVERS" || RESOLVER_ERROR="rewriting /etc/resolv.conf failed"
else
  RESOLVER_ERROR=$FW_ERROR
fi

STEP="loading the closed rules"
if ! load closed; then
  # No rule can be loaded at all (no NET_ADMIN, or no nftables support in the kernel).
  trap - EXIT
  log "$FW_ERROR; outbound traffic is unrestricted"
  record not-applied "$FW_ERROR"
  exit 0
fi
[ -z "$OPTIONS_ERROR" ] || fail "$OPTIONS_ERROR"
[ -z "$RESOLVER_ERROR" ] || fail "$RESOLVER_ERROR"

if [ "$OPT_DEFAULT_ACTION" = deny ] && printf '%s\n' "$FW_PRESETS" | grep -qx github; then
  STEP="looking up $META_HOST"
  lookup_meta_host || fail "$FW_ERROR"
  STEP="loading the closed rules with $META_HOST"
  load pinned || fail "$FW_ERROR"
  STEP="fetching $META_URL"
  fetch_meta || fail "$FW_ERROR"
fi

STEP="loading the rules"
ENTRIES=$(
  {
    printf '%s\n' "$FW_ALLOWED_CIDRS" "$GITHUB_LINES" | awk 'NF == 3 { print "allow", $0 }'
    printf '%s\n' "$FW_DENIED_CIDRS" | awk 'NF == 3 { print "deny", $0 }'
  } | sort -u
)
load full || fail "$FW_ERROR"

STEP="starting the resolver"
start_dnsmasq || fail "$FW_ERROR"

STEP="pointing /etc/resolv.conf at the resolver"
write_nameservers 127.0.0.1 || fail "rewriting /etc/resolv.conf failed"

trap - EXIT
record applied ""
log "applied (defaultAction=$OPT_DEFAULT_ACTION, presets=$OPT_PRESETS, GitHub ranges: $GITHUB_RANGES)"
