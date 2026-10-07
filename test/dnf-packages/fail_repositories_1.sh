#!/usr/bin/env bash
# Scenario fail_repositories_1 (scenarios.json): this script runs install.sh in a container whose repositories it has
# broken, one way at a time. Spec scenarios "Refresh is explicitly requested" (a skippable repository that cannot be
# reached, without and beside existing metadata), "Explicit timeout reaches network operations" (a repository that
# accepts the connection and never answers), "Skippable repository is skipped", and "Unverifiable package fails".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly UNAVAILABLE_REPOSITORY="/etc/yum.repos.d/unavailable.repo"
readonly STALLED_REPOSITORY="/etc/yum.repos.d/stall.repo"
readonly REPOSITORIES_BACKUP="/tmp/yum.repos.d.backup"
readonly STALL_PORT=8099
readonly STALL_LOG="/tmp/stall-connections"
readonly WRONG_KEY="/tmp/wrong-key"

# Listens on the loopback port STALL_PORT and holds each connection open without answering, one after the other, adding
# a line to STALL_LOG for each. gawk is part of every compatibility image; python3 and perl are not.
stalled_repository() {
  exec gawk -v port="${STALL_PORT}" -v log_file="${STALL_LOG}" 'BEGIN {
    service = "/inet/tcp/" port "/0/0"
    while (1) {
      status = (service |& getline request)
      if (status < 0) exit 1
      if (status > 0) {
        print "connection" >>log_file
        close(log_file)
        while ((service |& getline request) > 0) { }
      }
      close(service)
    }
  }'
}

# The port answers a connection attempt, so the listener is ready.
stalled_repository_listens() {
  (exec 3<>"/dev/tcp/127.0.0.1/${STALL_PORT}") 2>/dev/null
}

reached_the_stalled_repository() {
  [[ -s "${STALL_LOG}" ]]
}

# Removes every key from the RPM keyring and points every repository at a key file that holds no key, so that no
# package signature can be verified. Prints the number of gpgkey lines it changed.
make_signatures_unverifiable() {
  local keys
  readarray -t keys < <(rpm -qa 'gpg-pubkey*')
  if [[ "${#keys[@]}" -gt 0 ]]; then rpm -e "${keys[@]}"; fi
  echo 'not a public key' >"${WRONG_KEY}"
  sed -i "s|^gpgkey=.*|gpgkey=file://${WRONG_KEY}|" /etc/yum.repos.d/*.repo
  cat /etc/yum.repos.d/*.repo | grep --count --line-regexp "gpgkey=file://${WRONG_KEY}"
}

database_before="$(rpm_database)"

# One repository beside the image's own answers nothing, and the image marks it as skippable.
cat >"${UNAVAILABLE_REPOSITORY}" <<'EOF'
[unavailable]
name=unavailable
baseurl=http://127.0.0.1:9/
enabled=1
skip_if_unavailable=1
gpgcheck=1
EOF
run_install PACKAGES=bc REFRESHPOLICY=always NETWORKTIMEOUT=1
check "refreshPolicy=always with an unavailable skippable repository fails" failed
check "refreshPolicy=always with an unavailable skippable repository does not install bc" not_installed bc
check "refreshPolicy=always with an unavailable skippable repository changes no installed package" \
  rpm_database_is "${database_before}"

# The only enabled repository accepts the connection and never answers.
cp -a /etc/yum.repos.d "${REPOSITORIES_BACKUP}"
sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/*.repo
cat >"${STALLED_REPOSITORY}" <<EOF
[stall]
name=stall
baseurl=http://127.0.0.1:${STALL_PORT}/
enabled=1
skip_if_unavailable=0
gpgcheck=1
retries=1
EOF
stalled_repository &
stall_pid=$!
until stalled_repository_listens; do sleep 0.1; done
configuration_before="$(dnf_configuration)"
SECONDS=0
run_install PACKAGES=bc REFRESHPOLICY=always NETWORKTIMEOUT=1
elapsed="${SECONDS}"
kill "${stall_pid}"
check "networkTimeout=1 with a stalled repository fails the feature" failed
check "the request reached the stalled repository" reached_the_stalled_repository
check "networkTimeout=1 bounds the stalled request: it took ${elapsed} s, under 45 s" test "${elapsed}" -lt 45
check "with a stalled repository bc is not installed" not_installed bc
check "with a stalled repository no installed package changed" rpm_database_is "${database_before}"
check "the timeout is not written to the dnf configuration" dnf_configuration_is "${configuration_before}"
rm -rf /etc/yum.repos.d
mv "${REPOSITORIES_BACKUP}" /etc/yum.repos.d

# The unavailable skippable repository is back beside the image's own.
configuration_before="$(dnf_configuration)"
run_install PACKAGES=bc REFRESHPOLICY=default CLEANUP=none
check "refreshPolicy=default skips the unavailable skippable repository and succeeds" exited_with 0
check "bc is installed from the other repositories" installed bc
check "premise: the image holds repository metadata" has_metadata
run_install PACKAGES=file REFRESHPOLICY=always CLEANUP=none
check "refreshPolicy=always fails for the same repository beside existing metadata" failed
check "refreshPolicy=always installs nothing from the repositories that answered: file is not installed" \
  not_installed file
check "no run wrote skip_if_unavailable to the dnf configuration" dnf_configuration_is "${configuration_before}"
rm "${UNAVAILABLE_REPOSITORY}"

changed="$(make_signatures_unverifiable)"
check "premise: every repository names a key file that holds no key" test "${changed}" -gt 0
database_before="$(rpm_database)"
run_install PACKAGES=file
check "a package whose signature cannot be verified fails the feature" failed
check "the unverifiable file is not installed" not_installed file
check "the failed verification changed no installed package and imported no key" rpm_database_is "${database_before}"

reportResults
