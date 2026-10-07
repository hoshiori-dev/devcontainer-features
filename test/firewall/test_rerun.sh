#!/usr/bin/env bash
# Scenario "test_rerun": default options. The harness cannot restart a container, so after the first start this test
# runs
# the start-time script once more as root, as the entrypoint does at a start: after deleting the feature's table
# ("Root removes the firewall"), stopping its resolver while /etc/resolv.conf still names it, adding a table of its own
# ("Other rules untouched"), and with variables named like the options ("Environment does not change the rules"). The
# re-run stands for "Restart re-applies the same rules"; the ruleset stands for "IPv6 default deny" and "Inbound
# connection still answered", which need IPv6 and a client outside the container. Then "Stale record" and "Changed
# environment" for the start check.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/checks.sh"

readonly RESOLVER_CONF="/run/firewall/dnsmasq.conf"
readonly RESOLVER_PID_FILE="/run/firewall/dnsmasq.pid"

work_dir="$(mktemp -d)"

# Prints the feature's two base chains with their rules.
chains() {
  nft list chain inet firewall output
  nft list chain inet firewall forward
}

# Prints every nftables table except the feature's.
other_tables() {
  local tables family name
  tables="$(nft list tables)"
  while read -r _ family name; do
    if [[ "${family} ${name}" == "inet firewall" ]]; then continue; fi
    nft list table "${family}" "${name}"
  done <<<"${tables}"
}

# Stops the feature's resolver and waits until 127.0.0.1:53 is free, as /proc/net/udp writes that address.
stop_resolver() {
  local pid
  local naps=0
  pid="$(cat "${RESOLVER_PID_FILE}")"
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

built_options_recorded() {
  record_is defaultAction deny && record_is presets github && record_is allowedCidrs "" \
    && record_is failureMode closed && record_is filterForward true
}

# Whether the resolver's configuration holds the lines that keep it to its own file and to 127.0.0.1, and names no
# other configuration to read.
resolver_reads_nothing_else() {
  local line
  for line in no-resolv no-hosts listen-address=127.0.0.1 bind-interfaces user=dnsmasq; do
    grep -qxF "${line}" "${RESOLVER_CONF}" || return 1
  done
  if grep -q -e '^conf-dir' -e '^resolv-file' "${RESOLVER_CONF}"; then return 1; fi
}

# Whether the feature's table, as the JSON listing in the file $1, has exactly one output and one forward base chain,
# each at filter priority (0) with policy drop, and no chain on another hook.
base_chains() {
  jq -e '[.nftables[] | select(.chain) | .chain | select(.table == "firewall")] as $chains
    | ($chains | map(select(.hook == "output" and .policy == "drop" and .prio == 0)) | length) == 1
    and ($chains | map(select(.hook == "forward" and .policy == "drop" and .prio == 0)) | length) == 1
    and ($chains | map(select(.hook == "input" or .hook == "prerouting" or .hook == "postrouting")) | length) == 0' \
    "$1"
}

# Whether the output chain holds its rules in the order of the design's Goal "Chains": loopback, replies, IPv6
# neighbour discovery, DNS to the resolvers, the refusal of other DNS, the nested bridges, the probe address, the
# denied before the allowed learned set for IPv4 and for IPv6, and last the refusal of everything else.
chain_order() {
  local chain
  chain="$(nft list chain inet firewall output)" || return 1
  awk '
    /oifname "lo" accept/ { lo = NR }
    /ct state established,related accept/ { replies = NR }
    /icmpv6 type .* ip6 hoplimit 255 accept/ { discovery = NR }
    /th dport 53 accept/ { dns = NR }
    /th dport 53 goto refuse/ { other_dns = NR }
    /oifname "docker0" accept/ { bridge = NR }
    /ip daddr 192.0.2.1 goto refuse/ { probe = NR }
    /ip daddr @denied_learned4 goto refuse/ { denied4 = NR }
    /ip daddr @allowed_learned4 accept/ { allowed4 = NR }
    /ip6 daddr @denied_learned6 goto refuse/ { denied6 = NR }
    /ip6 daddr @allowed_learned6 accept/ { allowed6 = NR }
    /^[[:space:]]*goto refuse$/ { last = NR }
    END {
      exit !(lo && lo < replies && replies < discovery && discovery < dns && dns < other_dns && other_dns < bridge \
        && bridge < probe && probe < denied4 && denied4 < allowed4 && allowed4 < denied6 && denied6 < allowed6 \
        && allowed6 < last)
    }' <<<"${chain}"
}

refusals_reject() {
  local chain
  chain="$(nft list chain inet firewall refuse)" || return 1
  [[ "${chain}" == *"reject with tcp reset"* && "${chain}" == *"reject with icmpx"* ]]
}

# Whether the start check exits non-zero and reports that the record of the current start is missing.
check_reports_no_current_record() {
  local report
  if report="$("${SHARE}/check.sh" 2>&1)"; then return 1; fi
  printf '%s\n' "${report}"
  [[ "${report}" == *"holds no record of the current start after 90 seconds, so the start was not applied"* ]]
}

check "the current start is recorded as applied" record_current applied
chains >"${work_dir}/chains_first.txt"

# Root removes the firewall
nft delete table inet firewall
check "after root deletes the feature's rules, a connection to registry.npmjs.org, which no option allows, succeeds" \
  reachable https://registry.npmjs.org/

# The state the re-run meets: a stopped resolver that /etc/resolv.conf still names, and a table of the test's own.
stop_resolver
# The two premises of the re-run are preconditions and not checks: without either, the checks after the re-run would
# pass without showing what their labels state, so the test stops here.
if ! names_local_resolver; then
  echo "the re-run must meet an /etc/resolv.conf that still names the stopped resolver, but it names another" >&2
  exit 1
fi
nft -f - <<'EOF'
table inet firewall-test {
  chain out {
    type filter hook output priority 10; policy accept;
    ip daddr 198.51.100.7 drop
  }
}
EOF
other_tables >"${work_dir}/other_before.txt"
if ! grep -q firewall-test "${work_dir}/other_before.txt"; then
  echo "the re-run must meet a table of the test's own, but the other tables hold no firewall-test" >&2
  exit 1
fi

# The re-run, with variables named like the options, in the spelling of devcontainer.json and in that of install.sh.
env defaultAction=allow presets=npm allowedCidrs=0.0.0.0/0 failureMode=warn filterForward=false \
  DEFAULTACTION=allow PRESETS=npm ALLOWEDCIDRS=0.0.0.0/0 FAILUREMODE=warn FILTERFORWARD=false \
  "${SHARE}/apply.sh"

# Restart re-applies the same rules
check "the firewall is applied again: the current start is recorded as applied" record_current applied
chains >"${work_dir}/chains_rerun.txt"
check "the firewall is applied again with the same rules" \
  diff "${work_dir}/chains_first.txt" "${work_dir}/chains_rerun.txt"

# Environment does not change the rules
check "the rules applied are those of the options the image was built with" built_options_recorded

# Other rules untouched
other_tables >"${work_dir}/other_after.txt"
check "the other nftables tables are unchanged" diff "${work_dir}/other_before.txt" "${work_dir}/other_after.txt"

# Deviation from shell-style.md (Tests): the labels from here to "Stale record" use the words of the design's Goals
# "Resolvers recorded once per container", "dnsmasq runs only from its own configuration", "Chains", and "Rejected,
# not dropped", invariants of the approach that no scenario of the spec states.
check "/etc/resolv.conf names the local resolver again once it answers" names_local_resolver
# The resolvers are Docker's for this container, so they are read when the test runs.
recorded_resolvers="$(cat /var/lib/firewall/resolvers)"
check "the start record names the recorded resolvers" record_is resolvers "${recorded_resolvers}"
resolver_pid="$(cat "${RESOLVER_PID_FILE}")"
resolver_command="$(tr '\0' ' ' <"/proc/${resolver_pid}/cmdline")"
check "dnsmasq starts with its own configuration file and nothing else" \
  test "${resolver_command}" = "dnsmasq --conf-file=${RESOLVER_CONF} "
check "dnsmasq reads no other configuration and listens on 127.0.0.1 only" resolver_reads_nothing_else
nft -j list table inet firewall >"${work_dir}/table.json"
check "the base chains are output and forward at filter priority with policy drop; there is no input chain" \
  base_chains "${work_dir}/table.json"
check "the output chain holds the rules in the designed order, the IPv6 pair included, and refuses the rest" \
  chain_order
check "refused TCP connections get a TCP reset, other protocols an ICMP rejection" refusals_reject

# Stale record. The check first waits its 90 seconds for a record of the current start.
cp "${RECORD}" "${work_dir}/record"
sed -i 's/^start=.*/start=1/' "${RECORD}"
check "with only a record of an earlier start, the check treats the current start as not applied" \
  check_reports_no_current_record
cp "${work_dir}/record" "${RECORD}"

# Changed environment: programs named like the check's tools first on PATH, and a file for ENV and BASH_ENV.
mkdir "${work_dir}/shadow"
for tool in sleep curl env sh cat awk sed; do
  printf '#!/bin/sh\necho shadowed %s\nexit 0\n' "${tool}" >"${work_dir}/shadow/${tool}"
  chmod +x "${work_dir}/shadow/${tool}"
done
echo 'echo sourced ENV' >"${work_dir}/shadow/rc"
clean_status=0
clean_output="$("${SHARE}/check.sh" 2>&1)" || clean_status=$?
shadowed_status=0
shadowed_output="$(PATH="${work_dir}/shadow:${PATH}" ENV="${work_dir}/shadow/rc" BASH_ENV="${work_dir}/shadow/rc" \
  "${SHARE}/check.sh" 2>&1)" || shadowed_status=$?
printf 'clean environment (%s): %s\n' "${clean_status}" "${clean_output}"
printf 'changed environment (%s): %s\n' "${shadowed_status}" "${shadowed_output}"
check "in a clean environment the check exits zero" test "${clean_status}" -eq 0
check "with a shadowing PATH, ENV, and BASH_ENV, the result and exit status are those of the clean run" \
  test "${shadowed_status}:${shadowed_output}" = "${clean_status}:${clean_output}"

rm -rf "${work_dir}"
reportResults
