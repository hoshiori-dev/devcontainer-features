#!/usr/bin/env bash
# Scenario fail_refresh_ubuntu (scenarios.json): this script runs install.sh in a container whose repositories it has
# broken, one way at a time. Spec scenarios "Failed refresh fails the feature" (one repository unreachable), "Refresh is
# explicitly requested" (an unavailable repository beside an existing index), "Unverifiable repository fails the
# refresh", and "Explicit timeout reaches network operations" (a repository that accepts the connection and never
# answers).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly UNREACHABLE_LIST="/etc/apt/sources.list.d/unreachable.list"
readonly SOURCES_BACKUP="/tmp/sources.list.d.backup"
readonly STALL_PORT_FILE="/tmp/stall-port"
readonly STALL_LOG="/tmp/stall-connections"

# A refresh that tolerates the failed repository succeeds, and bc then resolves: only a refresh that fails on any
# repository stops the feature here.
tolerant_refresh_leaves_bc_installable() {
  as_root apt-get update -qq && apt-get -s -qq install --no-install-recommends -- bc >/dev/null
}

# Points every source's Signed-By at another keyring the image ships, which did not sign the archive. Prints the
# number of lines it changed.
swap_signing_keys() {
  local configured keyring wrong=""
  configured="$(sed -n 's/^Signed-By: *//p' /etc/apt/sources.list.d/*.sources | sort -u)"
  for keyring in /usr/share/keyrings/*removed*.gpg /usr/share/keyrings/*.gpg; do
    if [[ ! -f "${keyring}" ]] || grep --line-regexp --quiet "${keyring}" <<<"${configured}"; then continue; fi
    wrong="${keyring}"
    break
  done
  if [[ -z "${wrong}" ]]; then
    echo "no other keyring in /usr/share/keyrings" >&2
    return 1
  fi
  as_root sed -i "s|^Signed-By: .*|Signed-By: ${wrong}|" /etc/apt/sources.list.d/*.sources
  cat /etc/apt/sources.list.d/*.sources | grep --count "^Signed-By: ${wrong}$"
}

names_the_signature() {
  output_matches 'not signed|NO_PUBKEY|signature' --ignore-case
}

# Listens on a free loopback port, writes the port to STALL_PORT_FILE, and holds every connection open without
# answering, adding a line to STALL_LOG for each. perl is part of both compatibility images.
stalled_repository() {
  perl -MIO::Socket::INET -e '
    my ($port_file, $log) = @ARGV;
    my $server = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1", LocalPort => 0) or die "listen: $!";
    open(my $out, ">", $port_file) or die "open: $!";
    print $out $server->sockport, "\n";
    close($out);
    my @held;
    while (my $connection = $server->accept) {
      push @held, $connection;
      open(my $entry, ">>", $log) or die "open: $!";
      print $entry "connection\n";
      close($entry);
    }
  ' "${STALL_PORT_FILE}" "${STALL_LOG}"
}

reached_the_stalled_repository() {
  [[ -s "${STALL_LOG}" ]]
}

status_before="$(dpkg_status)"

# One repository beside the image's own answers nothing.
echo 'deb http://127.0.0.1:9/ unreachable main' | as_root tee "${UNREACHABLE_LIST}" >/dev/null
run_install PACKAGES=bc
check "with one unreachable repository the refresh fails the feature" failed
check "the failure names the unreachable repository" printed "127.0.0.1:9"
check "with one unreachable repository nothing is installed" dpkg_status_is "${status_before}"
check "premise: a refresh that tolerates the unreachable repository leaves bc installable" \
  tolerant_refresh_leaves_bc_installable

# The tolerant refresh left an index, so only refreshPolicy=always checks the repositories again.
check "premise: the image holds a package index" has_index
run_install PACKAGES=bc REFRESHPOLICY=always NETWORKTIMEOUT=1
check "refreshPolicy=always with an unavailable repository fails beside an existing index" failed
check "refreshPolicy=always with an unavailable repository installs nothing" dpkg_status_is "${status_before}"
as_root rm "${UNREACHABLE_LIST}"
as_root sh -c 'rm -rf /var/lib/apt/lists/*'

as_root cp -a /etc/apt/sources.list.d "${SOURCES_BACKUP}"
swapped="$(swap_signing_keys)"
check "premise: every source names a keyring that did not sign its archive" test "${swapped}" -gt 0
run_install PACKAGES=bc
check "a repository that cannot be verified fails the refresh" failed
check "the failure names the signature" names_the_signature
check "with an unverifiable repository nothing is installed" dpkg_status_is "${status_before}"
as_root sh -c "rm -rf /etc/apt/sources.list.d && mv ${SOURCES_BACKUP} /etc/apt/sources.list.d"
as_root sh -c 'rm -rf /var/lib/apt/lists/*'

stalled_repository &
stall_pid=$!
# The wait ends after 30 s, so a listener that never comes up fails the premise below.
waited=0
until [[ -s "${STALL_PORT_FILE}" || "${waited}" -ge 30 ]]; do
  sleep 1
  waited=$((waited + 1))
done
check "premise: the stalled repository listens and has written its port" test -s "${STALL_PORT_FILE}"
as_root sh -c 'rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*'
printf 'deb http://127.0.0.1:%s/ stalled main\n' "$(<"${STALL_PORT_FILE}")" \
  | as_root tee /etc/apt/sources.list >/dev/null
configuration_before="$(apt_configuration)"
SECONDS=0
run_install PACKAGES=bc REFRESHPOLICY=always NETWORKTIMEOUT=1
elapsed="${SECONDS}"
kill "${stall_pid}"
check "networkTimeout=1 with a stalled repository fails the feature" failed
check "the request reached the stalled repository" reached_the_stalled_repository
check "networkTimeout=1 bounds the stalled request: it took ${elapsed} s, under 45 s" test "${elapsed}" -lt 45
check "with a stalled repository nothing is installed" dpkg_status_is "${status_before}"
check "the timeout is not written to the apt configuration" apt_configuration_is "${configuration_before}"

reportResults
