#!/bin/bash
# Scenario rerun: default options. The harness cannot restart a container, so after the first start
# this re-runs the start-time script as root once, after deleting the feature's table (Root removes
# the firewall), stopping its resolver while /etc/resolv.conf still names it, adding a table of its
# own (Other rules untouched), and setting variables named like the options (Environment does not
# change the rules). Covers Restart re-applies the same rules, IPv6 default deny and Inbound
# connection still answered by ruleset, Stale record, and Changed environment.

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
. "$(dirname "$0")/helpers.sh"

check "the first start is recorded as applied" record_current applied
chains() {
  nft list chain inet firewall output && nft list chain inet firewall forward
}
chains >/tmp/chains-first.txt

# Root removes the firewall
nft delete table inet firewall
check "with the table deleted by root, registry.npmjs.org is reachable" reachable https://registry.npmjs.org/

stop_resolver
check "resolv.conf still names the stopped resolver" names_local_resolver
nft -f - <<'EOF'
table inet firewall-test {
  chain out {
    type filter hook output priority 10; policy accept;
    ip daddr 198.51.100.7 drop
  }
}
EOF
other_tables() {
  nft list tables | grep -v '^table inet firewall$' | while read -r _ family name; do
    nft list table "$family" "$name"
  done
}
other_tables >/tmp/other-before.txt
check "a table of the test's own exists" grep -q firewall-test /tmp/other-before.txt

env defaultAction=allow presets=npm allowedCidrs=0.0.0.0/0 failureMode=warn filterForward=false \
  DEFAULTACTION=allow PRESETS=npm ALLOWEDCIDRS=0.0.0.0/0 FAILUREMODE=warn FILTERFORWARD=false \
  "$SHARE/apply.sh"

check "the re-run is recorded as applied for the current start" record_current applied
built_options() {
  record_is defaultAction deny && record_is presets github && record_is allowedCidrs '' \
    && record_is failureMode closed && record_is filterForward true
}
check "variables named like the options change nothing" built_options
chains >/tmp/chains-rerun.txt
check "the re-run loads the same chains as the first start" diff /tmp/chains-first.txt /tmp/chains-rerun.txt
other_tables >/tmp/other-after.txt
check "other tables are unchanged" diff /tmp/other-before.txt /tmp/other-after.txt
check "resolv.conf names the resolver again" names_local_resolver
check "the recorded resolvers are the record's" test "$(cat /var/lib/firewall/resolvers)" = "$(record_field resolvers)"
check "the resolver runs from its own configuration only" \
  test "$(tr '\0' ' ' <"/proc/$(cat /run/firewall/dnsmasq.pid)/cmdline")" = "dnsmasq --conf-file=/run/firewall/dnsmasq.conf "
resolver_configuration() {
  grep -qx no-resolv /run/firewall/dnsmasq.conf && grep -qx no-hosts /run/firewall/dnsmasq.conf \
    && grep -qx listen-address=127.0.0.1 /run/firewall/dnsmasq.conf \
    && grep -qx bind-interfaces /run/firewall/dnsmasq.conf && grep -qx user=dnsmasq /run/firewall/dnsmasq.conf \
    && ! grep -q -e '^conf-dir' -e '^resolv-file' /run/firewall/dnsmasq.conf
}
check "the resolver configuration reads nothing else and listens on 127.0.0.1 only" resolver_configuration

# Chain contents
nft -j list table inet firewall >/tmp/table.json
base_chains() {
  jq -e '[.nftables[] | select(.chain) | .chain | select(.table == "firewall")] as $c
    | ($c | map(select(.hook == "output" and .policy == "drop" and .prio == 0)) | length) == 1
    and ($c | map(select(.hook == "forward" and .policy == "drop" and .prio == 0)) | length) == 1
    and ($c | map(select(.hook == "input" or .hook == "prerouting" or .hook == "postrouting")) | length) == 0' \
    /tmp/table.json
}
check "ruleset: output and forward chains with policy drop, no input chain" base_chains
chain_order() {
  nft list chain inet firewall output | awk '
    /oifname "lo" accept/ { lo = NR }
    /ct state established,related accept/ { ct = NR }
    /icmpv6 type .* ip6 hoplimit 255 accept/ { nd = NR }
    /th dport 53 accept/ { dns = NR }
    /th dport 53 goto refuse/ { dnsref = NR }
    /oifname "docker0" accept/ { br = NR }
    /ip daddr 192.0.2.1 goto refuse/ { probe = NR }
    /ip daddr @denied_learned4 goto refuse/ { d4 = NR }
    /ip daddr @allowed_learned4 accept/ { a4 = NR }
    /ip6 daddr @denied_learned6 goto refuse/ { d6 = NR }
    /ip6 daddr @allowed_learned6 accept/ { a6 = NR }
    /^[[:space:]]*goto refuse$/ { last = NR }
    END { exit !(lo && lo < ct && ct < nd && nd < dns && dns < dnsref && dnsref < br && br < probe \
      && probe < d4 && d4 < a4 && a4 < d6 && d6 < a6 && a6 < last) }'
}
check "ruleset: output rules in the designed order, IPv6 included, refusing the rest" chain_order
refuse_chain() {
  nft list chain inet firewall refuse | grep -q 'reject with tcp reset' \
    && nft list chain inet firewall refuse | grep -q 'reject with icmpx'
}
check "ruleset: refusals reset TCP and reject the rest" refuse_chain

# Stale record: the check waits for the current start's record and then fails.
cp "$RECORD" /tmp/record.saved
sed -i 's/^start=.*/start=1/' "$RECORD"
check "a record of an earlier start fails the check" check_fails
cp /tmp/record.saved "$RECORD"

# Changed environment
mkdir -p /tmp/shadow
for tool in sleep curl env sh cat awk sed; do
  printf '#!/bin/sh\necho shadowed %s\nexit 0\n' "$tool" >"/tmp/shadow/$tool"
  chmod +x "/tmp/shadow/$tool"
done
echo 'echo sourced ENV' >/tmp/shadow/rc
clean_output=$("$SHARE/check.sh" 2>&1)
clean_status=$?
shadowed_output=$(PATH="/tmp/shadow:$PATH" ENV=/tmp/shadow/rc BASH_ENV=/tmp/shadow/rc "$SHARE/check.sh" 2>&1)
shadowed_status=$?
echo "clean ($clean_status): $clean_output"
echo "shadowed ($shadowed_status): $shadowed_output"
check "a shadowing PATH, ENV, and BASH_ENV do not change the check" \
  test "$clean_status:$clean_output" = "$shadowed_status:$shadowed_output" -a "$clean_status" = 0

reportResults
