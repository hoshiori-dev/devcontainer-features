#!/bin/sh
# Scenario fail_refresh_alpine_3_22 (scenarios.json): this script runs install.sh in a container whose repositories it
# has broken, one way at a time. Spec scenarios "Unavailable repository fails the feature" (one repository answers
# HTTP 404), "Refresh is explicitly requested" (an unavailable repository beside the image's own), "Unverifiable
# repository fails the refresh", and "Explicit timeout reaches network operations" (a repository that accepts the
# connection and never answers).
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly REPOSITORIES_BACKUP="/tmp/repositories.backup"
readonly KEYS_BACKUP="/tmp/keys.moved"
readonly STALL_PORT=8099
readonly STALL_HOLD="/tmp/stall-hold"
readonly STALL_REQUEST="/tmp/stall-request"

# Prints the number of lines of /etc/apk/repositories that end with $1.
repository_lines_ending_with() {
  grep -c -- "$1\$" /etc/apk/repositories || true
}

# apk add alone skips the failing repository and would install file from the others: only the feature's refresh,
# which fails on any repository, stops the installation.
apk_add_alone_would_install_file() {
  apk --no-cache add --simulate file
}

no_trusted_key() {
  no_trusted_key_entries="$(ls -A /etc/apk/keys)" || return 1
  [ -z "${no_trusted_key_entries}" ]
}

stalled_repository_listens() {
  netstat -ltn | grep -q "127.0.0.1:${STALL_PORT} "
}

reached_the_stalled_repository() {
  grep -q '^GET .*APKINDEX' "${STALL_REQUEST}"
}

state_before="$(apk_state)"
cp -p /etc/apk/repositories "${REPOSITORIES_BACKUP}"

# A repository line whose index answers HTTP 404, beside the image's own.
sed -n 's|/main$|/nonexistent|p' "${REPOSITORIES_BACKUP}" >>/etc/apk/repositories
check "premise: one repository line names the nonexistent repository" \
  test "$(repository_lines_ending_with /nonexistent)" = 1
check "premise: apk add alone skips the failing repository and would install file" apk_add_alone_would_install_file
run_install PACKAGES=file
check "with one repository whose index cannot be fetched the feature fails" install_failed
check "the failure is the refresh's" printed "apk update failed"
check "with one repository whose index cannot be fetched file is not installed" not_installed file
check "with one repository whose index cannot be fetched nothing changed" apk_state_is "${state_before}"
cp -p "${REPOSITORIES_BACKUP}" /etc/apk/repositories

# A repository nothing listens on, beside the image's own.
echo 'http://127.0.0.1:9/unavailable' >>/etc/apk/repositories
run_install PACKAGES=tree REFRESHPOLICY=always NETWORKTIMEOUT=1
check "refreshPolicy=always with an unavailable repository fails" install_failed
check "refreshPolicy=always with an unavailable repository does not install tree" not_installed tree
cp -p "${REPOSITORIES_BACKUP}" /etc/apk/repositories

mkdir "${KEYS_BACKUP}"
mv /etc/apk/keys/* "${KEYS_BACKUP}/"
check "premise: the image trusts no key" no_trusted_key
run_install PACKAGES=file
check "a repository that cannot be verified fails the feature" install_failed
check "the failure names the untrusted signature" printed "UNTRUSTED"
check "with an unverifiable repository file is not installed" not_installed file
check "with an unverifiable repository nothing changed" apk_state_is "${state_before}"
mv "${KEYS_BACKUP}"/* /etc/apk/keys/

# A repository that listens on a loopback port, writes what the first connection sends to STALL_REQUEST, and holds
# that connection open without answering: its input is a named pipe nobody writes to. nc is a BusyBox applet of both
# compatibility images.
mkfifo "${STALL_HOLD}"
nc -l -s 127.0.0.1 -p "${STALL_PORT}" <>"${STALL_HOLD}" >"${STALL_REQUEST}" 2>/dev/null &
stall_pid=$!
until stalled_repository_listens; do sleep 1; done
printf 'http://127.0.0.1:%s/unavailable\n' "${STALL_PORT}" >/etc/apk/repositories
configuration_before="$(apk_configuration)"
started="$(date +%s)"
run_install PACKAGES=tree REFRESHPOLICY=always NETWORKTIMEOUT=1
elapsed=$(($(date +%s) - started))
kill "${stall_pid}"
check "networkTimeout=1 with a stalled repository fails the feature" install_failed
check "the request reached the stalled repository" reached_the_stalled_repository
check "networkTimeout=1 bounds the stalled request: it took ${elapsed} s, under 45 s" test "${elapsed}" -lt 45
check "with a stalled repository tree is not installed" not_installed tree
check "the timeout is not written to the apk configuration" apk_configuration_is "${configuration_before}"

reportResults
