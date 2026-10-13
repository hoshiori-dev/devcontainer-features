#!/usr/bin/env bash
# Scenario test_download_controls_1 (scenarios.json): this script runs install.sh with connectTimeout,
# transferTimeout, and downloadRetries against repositories it serves itself on loopback ports (fixture_server.py), so
# that no check waits for a public mirror to be slow or broken: one that answers no connection attempt, one that
# accepts a request and sends nothing, one that fails every request and counts them, and one that sends a package file
# in pieces. The last one serves a copy of the metadata of the image's repository with its signature, and a package
# file from that repository. Spec scenarios "Explicit connect timeout reaches downloads", "Explicit transfer timeout
# reaches downloads", "Active transfer outlasts the transfer timeout", "Native retries are inherited", "Explicit
# retries reach metadata requests", "Retries turned off", "Image settings stay in effect beside an override", "Proxy
# configuration is inherited", and "Signature checking holds beside an override". A time is asserted between the
# option's value and the timeout libzypp has without the option, 60 seconds to connect and 180 for a transfer.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

SERVER="$(dirname "$0")/fixture_server.py"
readonly SERVER
readonly SILENT_PORT=8101
readonly STALLING_PORT=8102
readonly FAILING_PORT=8103
readonly SLOW_PORT=8104
readonly STALLING_LOG="/tmp/stalling.log"
readonly FAILING_LOG="/tmp/failing.log"
readonly SLOW_DIRECTORY="/tmp/slow"
# A setting of the image, as a file libzypp reads before the feature's: three attempts for each metadata request.
readonly IMAGE_TRIES_FILE="/etc/zypp/zypp.conf.d/50-image-tries.conf"

servers=()

stop_servers() {
  if [[ "${#servers[@]}" -gt 0 ]]; then kill "${servers[@]}" 2>/dev/null || true; fi
}

# Starts fixture_server.py in the background with the arguments given.
start_server() {
  python3 "${SERVER}" "$@" >/dev/null 2>&1 &
  servers+=($!)
}

# Waits until the port $1 accepts a connection.
wait_for_port() {
  local attempt
  for attempt in {1..50}; do
    if (: <"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then return 0; fi
    sleep 0.2
  done
  echo "nothing listens on port $1 after ${attempt} attempts" >&2
  return 1
}

# Defines the enabled repository $1 at the loopback port $2.
add_repository() {
  printf '[%s]\nname=%s fixture\nenabled=1\nautorefresh=1\nbaseurl=http://127.0.0.1:%s/\n' "$1" "$1" "$2" \
    >"/etc/zypp/repos.d/$1.repo"
}

# Prints how often the failing server received each request, as "<count> <METHOD> <path>" lines.
request_counts() {
  sort "${FAILING_LOG}" | uniq -c | sed 's/^ *//'
}

# The failing server received its first request exactly $1 times.
first_request_came() {
  local first
  first="$(sed -n 1p "${FAILING_LOG}")"
  if [[ "$(grep -cxF -- "${first}" "${FAILING_LOG}")" -ne "$1" ]]; then
    printf 'the server received "%s" not %s times; all requests:\n%s\n' "${first}" "$1" "$(request_counts)" >&2
    return 1
  fi
}

# The failing server received no request, counted by method and path, more than $1 times.
no_request_came_more_than() {
  local count request
  while read -r count request; do
    if [[ "${count}" -gt "$1" ]]; then
      printf 'the server received "%s" %s times\n' "${request}" "${count}" >&2
      return 1
    fi
  done < <(request_counts)
}

# The failing server, as a proxy, received a request for another host: one with an absolute URL, or a CONNECT.
proxy_was_asked() {
  grep -Eq '^((GET|HEAD) http://|CONNECT )' "${FAILING_LOG}"
}

# The feature ended at least $1 seconds after the stalling server accepted the first connection of the run; the
# script empties the server's log before the run.
ended_after_accepting() {
  local accepted now
  accepted="$(sed -n 1p "${STALLING_LOG}")"
  now="$(date +%s)"
  if [[ -z "${accepted}" || "$((now - accepted))" -lt "$1" ]]; then
    echo "the server accepted at '${accepted}', and the run had ended at ${now}" >&2
    return 1
  fi
}

# rpm lists documentation files for the package $1, and none of them is on disk: the image's libzypp configuration
# excludes documentation.
documentation_is_excluded() {
  local file files
  files="$(rpm -q --docfiles "$1")"
  if [[ -z "${files}" ]]; then
    echo "$1 has no documentation files" >&2
    return 1
  fi
  while read -r file; do
    if [[ -e "${file}" ]]; then
      echo "${file} is installed" >&2
      return 1
    fi
  done <<<"${files}"
}

# Prints the signing keys the RPM database trusts.
trusted_keys() {
  rpm -qa 'gpg-pubkey*' | sort
}

trap stop_servers EXIT

# python3 runs the fixtures. The metadata refreshed for it is what the slow repository then serves.
zypper --non-interactive install --no-recommends python3
oss="$(enabled_alias repo-oss)"
check "premise: the image enables a repository whose alias ends in repo-oss" test -n "${oss}"
mkdir -p "${SLOW_DIRECTORY}/packages"
cp -R "/var/cache/zypp/raw/${oss}/repodata" "${SLOW_DIRECTORY}/"
check "premise: the copied metadata carries the signature of the image's repository" \
  test -s "${SLOW_DIRECTORY}/repodata/repomd.xml.asc"
zypper --non-interactive --no-refresh download bc
while read -r package_file; do
  cp "${package_file}" "${SLOW_DIRECTORY}/packages/"
done < <(package_files)
zypper --non-interactive clean --all

# The silent server is started first and not waited for: a connection to it would never be answered.
start_server silent "${SILENT_PORT}"
start_server stalling "${STALLING_PORT}" "${STALLING_LOG}"
start_server failing "${FAILING_PORT}" "${FAILING_LOG}"
start_server slow "${SLOW_PORT}" "${SLOW_DIRECTORY}" 12
wait_for_port "${STALLING_PORT}"
wait_for_port "${FAILING_PORT}"
wait_for_port "${SLOW_PORT}"
add_repository silent "${SILENT_PORT}"
add_repository stalling "${STALLING_PORT}"
add_repository failing "${FAILING_PORT}"
add_repository slow "${SLOW_PORT}"
database_before="$(rpm_database)"

run_install PACKAGES=bc REPOSITORIES=silent CONNECTTIMEOUT=2
check "connectTimeout=2 fails when the repository answers no connection attempt" failed
check "connectTimeout=2 fails no sooner than 2 seconds after the start" took_at_least 2
check "connectTimeout=2 fails sooner than the 60 seconds libzypp waits without the option" took_less_than 60
check "after the connect timeout nothing is installed" rpm_database_is "${database_before}"

: >"${STALLING_LOG}"
run_install PACKAGES=bc REPOSITORIES=stalling TRANSFERTIMEOUT=4
check "transferTimeout=4 fails when the server accepts a metadata request and sends nothing" failed
check "transferTimeout=4 fails no sooner than 4 seconds after the server accepted the request" ended_after_accepting 4
check "transferTimeout=4 fails sooner than the 180 seconds libzypp waits without the option" took_less_than 180
check "after the transfer timeout nothing is installed" rpm_database_is "${database_before}"

run_install PACKAGES=bc REPOSITORIES=slow TRANSFERTIMEOUT=4 CLEANUP=none
check "transferTimeout=4 succeeds when the package file arrives in pieces one second apart" exited_with 0
check "the transfer lasted longer than the 4 seconds of transferTimeout" took_at_least 5
check "bc, whose file arrived in pieces, is installed" installed bc
check "with transferTimeout set the image's exclusion of documentation is followed for bc" \
  documentation_is_excluded bc
zypper --non-interactive remove bc
run_install PACKAGES=bc REPOSITORIES=slow CLEANUP=none
check "premise: bc installs from the same repository with every timeout and retry option empty" exited_with 0
check "with the options empty the image's exclusion of documentation is followed for bc alike" \
  documentation_is_excluded bc

: >"${FAILING_LOG}"
run_install PACKAGES=tree REPOSITORIES=failing DOWNLOADRETRIES=2
check "downloadRetries=2 fails when the repository fails every metadata request" failed
check "with downloadRetries=2 the first failing request came 3 times" first_request_came 3
check "with downloadRetries=2 no request came more than 3 times" no_request_came_more_than 3
check "no tree is installed" not_installed tree

printf '[main]\ndownload.max_silent_tries = 3\n' >"${IMAGE_TRIES_FILE}"
: >"${FAILING_LOG}"
run_install PACKAGES=tree REPOSITORIES=failing
check "with an empty downloadRetries the feature fails against the failing repository" failed
check "with an empty downloadRetries the 3 attempts the image configures stay in effect" first_request_came 3
: >"${FAILING_LOG}"
run_install PACKAGES=tree REPOSITORIES=failing DOWNLOADRETRIES=0
check "downloadRetries=0 fails when the repository fails every metadata request" failed
check "with downloadRetries=0 no request came more than once, although the image configures 3 attempts" \
  no_request_came_more_than 1
check "with downloadRetries=0 the server did receive requests" test -s "${FAILING_LOG}"
rm "${IMAGE_TRIES_FILE}"

# A proxy of the build environment: the failing server stands for it, and logs what it is asked for.
: >"${FAILING_LOG}"
run_install PACKAGES=tree http_proxy="http://127.0.0.1:${FAILING_PORT}" https_proxy="http://127.0.0.1:${FAILING_PORT}"
check "with a proxy in the build environment that fails every request the feature fails" failed
check "with every option at its default zypper asked the proxy" proxy_was_asked
: >"${FAILING_LOG}"
run_install PACKAGES=tree http_proxy="http://127.0.0.1:${FAILING_PORT}" \
  https_proxy="http://127.0.0.1:${FAILING_PORT}" REPOSITORIES="${oss}" EXACTNAMES=true LOCKTIMEOUT=5 \
  CONNECTTIMEOUT=30 TRANSFERTIMEOUT=60 DOWNLOADRETRIES=1
check "with the same proxy and every selection and network control set the feature fails" failed
check "with every selection and network control set zypper asked the proxy" proxy_was_asked
check "no tree is installed through the failing proxy" not_installed tree

# The image's repositories are signed by keys the RPM database no longer trusts.
rm /etc/zypp/repos.d/{silent,stalling,failing,slow}.repo
zypper --non-interactive clean --all >/dev/null
readarray -t keys < <(trusted_keys)
if [[ "${#keys[@]}" -gt 0 ]]; then rpm -e "${keys[@]}"; fi
check "premise: the RPM database trusts no key" test -z "$(trusted_keys)"
database_before="$(rpm_database)"
run_install PACKAGES=tree CONNECTTIMEOUT=30 TRANSFERTIMEOUT=60 DOWNLOADRETRIES=1
check "with timeouts and retries set, repositories signed by keys the image does not trust fail the feature" failed
check "no key is trusted and no package installed: the RPM database is unchanged" \
  rpm_database_is "${database_before}"
check "nothing is left of a temporary configuration file" no_override_left

reportResults
