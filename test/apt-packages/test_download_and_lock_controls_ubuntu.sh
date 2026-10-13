#!/usr/bin/env bash
# Scenario test_download_and_lock_controls_ubuntu (scenarios.json): the container has no network; this script publishes
# a repository of its own in it (repository.sh), serves it from a loopback address, and runs install.sh against it.
# Every scenario of the spec requirements "Download retries are bounded" and "Lock wait is scoped to installation"; the
# scenarios "Empty options inherit the image configuration", "Explicit option overrides its image setting", "Proxy
# settings are inherited", "Omitted downloadRetries", "Omitted lockTimeout", "Refresh ignores the target release", and
# "Earlier source and download controls do not persist"; and the design goal that an installation with none of the new
# options makes the calls of apt-packages 1.1.1.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"
# shellcheck source=/dev/null
source "$(dirname "$0")/repository.sh"

readonly CALL_LOG="/tmp/native-calls"
readonly CALL_STARTED="/tmp/native-call-started"
readonly LOGGING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly SERVER_PORT_FILE="/tmp/server-port"
readonly SERVER_MODE="/tmp/server-mode"
readonly SERVER_LOG="/tmp/server-requests"
readonly LOCK_HELD="/tmp/lock-held"
readonly IMAGE_SETTINGS="/etc/apt/apt.conf.d/99-scenario-settings"
readonly FRONTEND_LOCK="/var/lib/dpkg/lock-frontend"
readonly DATABASE_LOCK="/var/lib/dpkg/lock"
readonly INDEX_LOCK="/var/lib/apt/lists/lock"
readonly ARCHIVE_LOCK="/var/cache/apt/archives/lock"

# Prints the calls apt-packages 1.1.1 makes to refresh the index, install the package $1, and clean up. With a proxy
# URL in $2, each call is followed by the line the logging apt-get adds for that proxy variable.
phase_1_calls() {
  local call
  for call in "[update] [--error-on=any]" \
    "[install] [--yes] [--no-remove] [--option] [APT::Install-Recommends=false] [--option]\
 [APT::Install-Suggests=false] [--option] [APT::Cmd::Pattern-Only=true] [--option] [Dpkg::Options::=--force-confdef]\
 [--option] [Dpkg::Options::=--force-confold] [--] [$1]" \
    "[clean]"; do
    echo "CALL ${call}"
    if [[ -n "${2-}" ]]; then echo "PROXY $2"; fi
  done
}

# Serves the repository on a free loopback port, which it writes to SERVER_PORT_FILE, and adds a line with the time and
# the path of every request to SERVER_LOG. A request names a file by its path or, as a proxy receives it, by its URL.
# SERVER_MODE holds what a request for a package file gets: "serve" the file, "close" the connection without an answer,
# "missing" the answer that no such file exists, "stall" no answer on a connection that stays open. With "close-all"
# every request is closed without an answer. perl is part of both compatibility images.
serve_repository() {
  perl -MIO::Socket::INET -MPOSIX -e '
    my ($root, $port_file, $mode_file, $log) = @ARGV;
    my $server = IO::Socket::INET->new(Listen => 16, LocalAddr => "127.0.0.1", LocalPort => 0) or die "listen: $!";
    open(my $out, ">", $port_file) or die "open: $!";
    print $out $server->sockport, "\n";
    close($out);
    my @stalled;
    while (my $connection = $server->accept) {
      my $request = <$connection>;
      next unless defined $request;
      while (defined(my $header = <$connection>)) { last if $header =~ /^\r?$/; }
      my ($path) = $request =~ m{^GET (?:http://[^/]+)?(\S+)};
      open(my $mode_in, "<", $mode_file) or die "open: $!";
      chomp(my $mode = <$mode_in>);
      close($mode_in);
      open(my $entry, ">>", $log) or die "open: $!";
      printf $entry "%.2f %s\n", (POSIX::times())[0] / POSIX::sysconf(POSIX::_SC_CLK_TCK), $path;
      close($entry);
      my $package_file = $path =~ /\.deb$/;
      if ($mode eq "close-all" || ($package_file && $mode eq "close")) { close($connection); next; }
      if ($package_file && $mode eq "stall") { push @stalled, $connection; next; }
      my $file;
      if (($package_file && $mode eq "missing") || !open($file, "<", "$root$path")) {
        print $connection "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        close($connection);
        next;
      }
      binmode($file);
      my $content = do { local $/; <$file> };
      close($file);
      print $connection "HTTP/1.1 200 OK\r\nContent-Length: ", length($content), "\r\nConnection: close\r\n\r\n";
      print $connection $content;
      close($connection);
    }
  ' "${REPOSITORY}" "${SERVER_PORT_FILE}" "${SERVER_MODE}" "${SERVER_LOG}"
}

# From now on the server treats requests as the mode $1 says, and the request log starts empty.
server_mode() {
  echo "$1" >"${SERVER_MODE}"
  : >"${SERVER_LOG}"
}

# Makes the repository's two suites at the URL $1 the image's only sources and drops any index.
use_repository_at() {
  printf 'deb [signed-by=%s] %s %s main\n' "${REPOSITORY_KEYRING}" "$1" alpha "${REPOSITORY_KEYRING}" "$1" beta \
    | as_root tee "${REPOSITORY_SOURCES}" >/dev/null
  as_root sh -c 'rm -rf /var/lib/apt/lists/*'
}

# Prints how many requests the server got since the last server_mode; with "packages" in $1, those for a package file.
requests() {
  if [[ "${1-}" == packages ]]; then
    grep --count '\.deb$' "${SERVER_LOG}" || true
  else
    wc --lines <"${SERVER_LOG}"
  fi
}

# Prints the whole seconds that passed between the first and the last request since the last server_mode.
request_span() {
  awk 'NR == 1 { first = $1 } { last = $1 } END { printf "%d\n", last - first }' "${SERVER_LOG}"
}

# Takes the lock file $1 as dpkg and APT take it, with fcntl, and holds it for $2 seconds; LOCK_HELD exists while it
# does. The packed record is the struct flock of 64-bit Linux.
hold_lock() {
  # The quoted text is perl, which shellcheck does not recognize behind as_root.
  # shellcheck disable=SC2016
  as_root perl -MFcntl -e '
    my ($path, $seconds, $held) = @ARGV;
    sysopen(my $lock, $path, O_RDWR | O_CREAT, 0640) or die "open: $!";
    my $record = pack("s s x4 q q l x4", F_WRLCK, 0, 0, 0, 0);
    fcntl($lock, F_SETLK, $record) or die "lock: $!";
    open(my $mark, ">", $held) or die "open: $!";
    close($mark);
    sleep($seconds);
    unlink($held);
  ' "$1" "$2" "${LOCK_HELD}" &
  local waited=0
  # The wait ends after 30 s, so a holder that never takes the lock fails the checks that follow.
  until [[ -e "${LOCK_HELD}" || "${waited}" -ge 30 ]]; do
    sleep 1
    waited=$((waited + 1))
  done
}

# Waits until the holder of hold_lock has released the lock, for 30 s at most.
lock_holder_ends() {
  local waited=0
  until [[ ! -e "${LOCK_HELD}" || "${waited}" -ge 30 ]]; do
    sleep 1
    waited=$((waited + 1))
  done
}

lock_is_held() {
  [[ -e "${LOCK_HELD}" ]]
}

lock_is_released() {
  [[ ! -e "${LOCK_HELD}" ]]
}

# The image's APT configuration holds the settings given, each as one line.
image_sets() {
  printf '%s\n' "$@" | as_root tee "${IMAGE_SETTINGS}" >/dev/null
}

# The logged calls of the last run are exactly the lines $1.
calls_are() {
  if [[ "$(<"${CALL_LOG}")" != "$1" ]]; then
    printf 'the calls were:\n%s\n' "$(<"${CALL_LOG}")" >&2
    return 1
  fi
}

no_call_sets_a_lock_wait() {
  ! grep --ignore-case --quiet 'lock' "${CALL_LOG}"
}

# Runs install.sh as run_install does, with an apt-get that logs its calls, and keeps only this run's calls.
run_logged_install() {
  as_root rm -f "${CALL_LOG}"
  run_install PATH="${LOGGING_PATH}" "$@"
}

# Each package is in alpha at 1.0 and in beta at 2.0, and each check installs one of its own.
for package in plain controlled unretried once twice refreshed absent inherited-retries overridden-retries \
  inherited-timeout overridden-timeout refused waited-frontend waited-database expired index-locked archive-locked \
  inherited-wait overridden-wait proxied proxied-by-image; do
  add_package alpha "${package}" 1.0
  add_package beta "${package}" 2.0
done
publish_suite alpha alpha-code 1.0
publish_suite beta beta-code 2.0
use_suites alpha beta

# An apt-get that logs its arguments and the proxy variable it was given, notes when it started, and then runs the
# image's apt-get.
mkdir /tmp/bin
cat >/tmp/bin/apt-get <<LOGGER
#!/bin/sh
printf 'CALL' >>${CALL_LOG}
for argument do printf ' [%s]' "\${argument}" >>${CALL_LOG}; done
printf '\n' >>${CALL_LOG}
if [ -n "\${http_proxy-}" ]; then printf 'PROXY %s\n' "\${http_proxy}" >>${CALL_LOG}; fi
date +%s >${CALL_STARTED}
exec $(command -v apt-get) "\$@"
LOGGER
chmod +x /tmp/bin/apt-get

# Arguments of the feature's calls
configuration_before="$(apt_configuration)"
run_logged_install PACKAGES=plain
check "plain installs with none of the new options" exited_with 0
check "with none of the new options the feature makes exactly the calls of apt-packages 1.1.1: no release preference, \
no retry setting, no lock setting" calls_are "$(phase_1_calls plain)"

run_logged_install PACKAGES=controlled TARGETRELEASE=alpha INSTALLSUGGESTS=true CONFFILEPOLICY=replace \
  DOWNLOADRETRIES=2 LOCKTIMEOUT=5 NETWORKTIMEOUT=7 REFRESHPOLICY=always
check "controlled installs with every new option set" exited_with 0
check "the retry count and the timeout reach the refresh and the install call, each with its own value; the lock wait \
and the target release reach the install call alone; the refresh is called as it is without them; between the two \
the release fields of the binary package lists are listed for the check that the target release prefers a release" \
  calls_are \
  "CALL [--option] [Acquire::http::Timeout=7] [--option] [Acquire::https::Timeout=7] [--option] [Acquire::Retries=2]\
 [update] [--error-on=any]
CALL [indextargets] [Created-By: Packages]
CALL [--option] [Acquire::http::Timeout=7] [--option] [Acquire::https::Timeout=7] [--option] [Acquire::Retries=2]\
 [install] [--yes] [--no-remove] [--option] [APT::Install-Recommends=false] [--option] [APT::Install-Suggests=true]\
 [--option] [APT::Cmd::Pattern-Only=true] [--target-release] [alpha] [--option] [DPkg::Lock::Timeout=5] [--option]\
 [Dpkg::Options::=--refuse-confdef] [--option] [Dpkg::Options::=--force-confnew] [--] [controlled]
CALL [clean]"

run_logged_install PACKAGES=plain
check "a later invocation that sets none of the options succeeds" exited_with 0
check "the later invocation gives APT no release preference, retry count, or lock wait, excludes suggestions, and \
keeps changed configuration files" calls_are "$(phase_1_calls plain)"
check "the image's APT and dpkg configuration files are the same as before the first invocation" \
  apt_configuration_is "${configuration_before}"

serve_repository &
server=$!
# The wait ends after 30 s, so a server that never comes up fails the premise below.
waited=0
until [[ -s "${SERVER_PORT_FILE}" || "${waited}" -ge 30 ]]; do
  sleep 1
  waited=$((waited + 1))
done
check "premise: the repository's server listens and has written its port" test -s "${SERVER_PORT_FILE}"
port="$(<"${SERVER_PORT_FILE}")"
use_repository_at "http://127.0.0.1:${port}"
configuration_before="$(apt_configuration)"

# Download retries on the install call. APT makes two requests for each attempt at a package file and waits 1 s
# before the first retry and 2 s before the second.
server_mode close
run_install PACKAGES=unretried DOWNLOADRETRIES=0
check "downloadRetries=0 fails the feature when the connection of a download is closed without an answer" failed
check "with downloadRetries=0 the download is not retried: one attempt, two requests" test "$(requests packages)" -eq 2
check "with downloadRetries=0 no retry delay passes" test "$(request_span)" -lt 1
server_mode close
run_install PACKAGES=once DOWNLOADRETRIES=1
check "downloadRetries=1 fails the feature when the connection keeps being closed" failed
check "with downloadRetries=1 the download is retried once: two attempts, four requests" \
  test "$(requests packages)" -eq 4
check "with downloadRetries=1 APT's delay of 1 s passes before the retry" test "$(request_span)" -ge 1
server_mode close
run_install PACKAGES=twice DOWNLOADRETRIES=2
check "downloadRetries=2 fails the feature when the connection keeps being closed" failed
check "with downloadRetries=2 the download is retried twice: three attempts, six requests" \
  test "$(requests packages)" -eq 6
check "with downloadRetries=2 APT's growing delay passes: 1 s, then 2 s" test "$(request_span)" -ge 3

# Download retries on the refresh
server_mode close-all
run_install PACKAGES=refreshed REFRESHPOLICY=always DOWNLOADRETRIES=0
check "downloadRetries=0 fails the refresh when every connection is closed without an answer" failed
unretried_requests="$(requests)"
check "premise: the refresh without a retry made requests" test "${unretried_requests}" -gt 0
server_mode close-all
run_install PACKAGES=refreshed REFRESHPOLICY=always DOWNLOADRETRIES=1
check "downloadRetries=1 fails the refresh when every connection keeps being closed" failed
check "with downloadRetries=1 the refresh makes every request a second time" \
  test "$(requests)" -eq $((2 * unretried_requests))
check "with downloadRetries=1 APT's delay of 1 s passes before the refresh is retried" test "$(request_span)" -ge 1

server_mode missing
run_install PACKAGES=absent DOWNLOADRETRIES=2
check "downloadRetries=2 fails the feature when the repository answers that a package file does not exist" failed
check "the missing file is requested once" test "$(requests packages)" -eq 1

# Retry count and timeout of the image's APT configuration
image_sets 'Acquire::Retries "0";'
server_mode close
run_install PACKAGES=inherited-retries
check "with downloadRetries omitted the feature fails when the connection of a download is closed" failed
check "with downloadRetries omitted the image's retry count of 0 stays in effect: one attempt, two requests" \
  test "$(requests packages)" -eq 2
image_sets 'Acquire::Retries "1";'
server_mode close
run_install PACKAGES=overridden-retries DOWNLOADRETRIES=0
check "downloadRetries=0 overrides the image's retry count of 1: one attempt, two requests" \
  test "$(requests packages)" -eq 2

# Without a timeout of 1 s, APT would wait 30 s for an answer.
image_sets 'Acquire::Retries "0";' 'Acquire::http::Timeout "1";'
server_mode stall
SECONDS=0
run_install PACKAGES=inherited-timeout
elapsed="${SECONDS}"
check "with networkTimeout omitted the feature fails when a download gets no answer" failed
check "with networkTimeout omitted the image's timeout of 1 s stays in effect: the run took ${elapsed} s, under 20 s" \
  test "${elapsed}" -lt 20
image_sets 'Acquire::Retries "0";' 'Acquire::http::Timeout "25";'
server_mode stall
SECONDS=0
run_install PACKAGES=overridden-timeout NETWORKTIMEOUT=1
elapsed="${SECONDS}"
check "networkTimeout=1 overrides the image's timeout of 25 s: the run took ${elapsed} s, under 20 s" \
  test "${elapsed}" -lt 20
check "the image's retry count stays in effect beside the explicit timeout: one attempt, two requests" \
  test "$(requests packages)" -eq 2
as_root rm "${IMAGE_SETTINGS}"
check "no run against the server changed the image's APT or dpkg configuration" \
  apt_configuration_is "${configuration_before}"

# Lock wait
server_mode serve
hold_lock "${FRONTEND_LOCK}" 6
run_logged_install PACKAGES=refused
check "with lockTimeout omitted a held dpkg lock fails the feature, as apt-get does" failed
check "premise: the lock was still held when the feature failed" lock_is_held
check "with lockTimeout omitted no call of the failed run carries a lock setting" no_call_sets_a_lock_wait
check "the package is not installed" not_installed refused
lock_holder_ends

hold_lock "${FRONTEND_LOCK}" 4
run_install PACKAGES=waited-frontend LOCKTIMEOUT=60
check "lockTimeout=60 succeeds when dpkg's frontend lock is released after 4 s" exited_with 0
check "the feature waited until the frontend lock was released" lock_is_released
check "the package is installed after the wait for the frontend lock" installed waited-frontend
lock_holder_ends
hold_lock "${DATABASE_LOCK}" 4
run_install PACKAGES=waited-database LOCKTIMEOUT=60
check "lockTimeout=60 succeeds when dpkg's database lock is released after 4 s" exited_with 0
check "the feature waited until the database lock was released" lock_is_released
check "the package is installed after the wait for the database lock" installed waited-database
lock_holder_ends

status_before="$(dpkg_status)"
hold_lock "${FRONTEND_LOCK}" 12
run_logged_install PACKAGES=expired LOCKTIMEOUT=3
finished="$(date +%s)"
check "lockTimeout=3 fails the feature when the lock is held for longer" failed
check "premise: the lock was still held when the feature gave up" lock_is_held
check "the feature fails no earlier than 3 s after the install call started" \
  test $((finished - $(<"${CALL_STARTED}"))) -ge 3
check "the expired wait changes no package" dpkg_status_is "${status_before}"
lock_holder_ends

hold_lock "${INDEX_LOCK}" 8
SECONDS=0
run_install PACKAGES=index-locked LOCKTIMEOUT=60 REFRESHPOLICY=always
elapsed="${SECONDS}"
check "lockTimeout=60 fails the feature when another process holds the lock of the package index" failed
check "the refresh names the index lock" printed "${INDEX_LOCK}"
check "the refresh does not wait: the lock was still held, and the run took ${elapsed} s, not 60 s" lock_is_held
lock_holder_ends
hold_lock "${ARCHIVE_LOCK}" 8
SECONDS=0
run_install PACKAGES=archive-locked LOCKTIMEOUT=60
elapsed="${SECONDS}"
check "lockTimeout=60 fails the feature when another process holds the lock of the package archive" failed
check "the install call names the archive lock" printed "${ARCHIVE_LOCK}"
check "the download of package files does not wait: the lock was still held, and the run took ${elapsed} s, not 60 s" \
  lock_is_held
lock_holder_ends

# Lock wait and default release of the image's APT configuration
image_sets 'DPkg::Lock::Timeout "60";'
hold_lock "${FRONTEND_LOCK}" 4
run_install PACKAGES=inherited-wait
check "with lockTimeout omitted the image's lock wait of 60 s stays in effect: the feature succeeds" exited_with 0
check "the feature waited until the lock was released, as the image's configuration says" lock_is_released
lock_holder_ends
image_sets 'DPkg::Lock::Timeout "1";' 'APT::Default-Release "alpha";'
configuration_before="$(apt_configuration)"
hold_lock "${FRONTEND_LOCK}" 4
run_install PACKAGES=overridden-wait LOCKTIMEOUT=60
check "lockTimeout=60 overrides the image's lock wait of 1 s: the feature succeeds" exited_with 0
check "the feature waited until the lock was released, as the option says" lock_is_released
check "the image's default release stays in effect beside the explicit lock wait" has_version overridden-wait 1.0
check "the feature changes no configuration file of the image" apt_configuration_is "${configuration_before}"
lock_holder_ends
as_root rm "${IMAGE_SETTINGS}"

# Proxy settings. No host is named repository.invalid, so the package installs only through the proxy.
use_repository_at "http://repository.invalid"
proxy="http://127.0.0.1:${port}/"
run_logged_install PACKAGES=proxied http_proxy="${proxy}"
check "APT applies the proxy of the build environment: the package installs from a host only the proxy reaches" \
  installed proxied
check "the feature passes no proxy setting of its own and leaves the proxy variable as it was" \
  calls_are "$(phase_1_calls proxied "${proxy}")"
image_sets "Acquire::http::Proxy \"${proxy}\";"
run_logged_install PACKAGES=proxied-by-image
check "APT applies the proxy of the image's APT configuration" installed proxied-by-image
check "the feature passes no proxy setting beside the image's" calls_are "$(phase_1_calls proxied-by-image)"

kill "${server}"

reportResults
