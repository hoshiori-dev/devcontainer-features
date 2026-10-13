#!/usr/bin/env bash
# Scenario test_control_calls_1 (scenarios.json): the container has no network, the feature is installed with an empty
# list, and this script runs install.sh with the list bc while zypper is a stand-in that records each call's
# arguments, environment, and the feature's temporary configuration file (zypper_recorder.sh). It shows what the
# selection and network controls pass to zypper and what they leave behind. Spec scenarios "Undeclared settings are
# inherited", the six "Omitted ..." scenarios, "Only separators in repositories", "Native lock wait is inherited",
# "Explicit lock wait reaches zypper calls", "Explicit lock wait overrides an inherited one", "Native timeouts are
# inherited", "Native retries are inherited", "No override writes no file", "Override file holds only the overridden
# settings", "One timeout leaves the other inherited", "Override file is removed after success", "Override file is
# removed after failure", "Feature does not repeat a failed call", "Inherited ZYPP_CONF fails an explicit override",
# "Inherited ZYPP_CONF is kept without an override", and "Zypp configuration is unchanged"; and the accepted bounds of
# the four boundary scenarios with a non-empty list. It also shows that the file exists at the repository listing a
# selection begins with, the first zypper call of such a run.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly RECORD_DIR="/tmp/zypper-record"
# A PATH on which zypper is the recording stand-in, and mktemp and rm are stand-ins that record their environment.
readonly RECORDER_PATH="/tmp/recorder:/usr/sbin:/usr/bin:/sbin:/bin"
readonly ZYPP_CONF_FILE="/tmp/inherited-zypp.conf"

# The three zypper calls of version 1.0.1 for the list bc with every option at its default.
readonly DEFAULT_CALLS="--non-interactive refresh
--non-interactive --no-refresh install --no-recommends -- bc
--non-interactive clean --all"

# Runs install.sh with the recording stand-ins on PATH, after clearing what earlier runs recorded.
run_recorded() {
  rm -rf "${RECORD_DIR}"
  mkdir "${RECORD_DIR}"
  run_install PATH="${RECORDER_PATH}" "$@"
}

# The stand-in recorded exactly the calls $1, one line of arguments each.
calls_are() {
  local calls=""
  if [[ -e "${RECORD_DIR}/calls" ]]; then calls="$(<"${RECORD_DIR}/calls")"; fi
  if [[ "${calls}" != "$1" ]]; then
    printf 'zypper was called with:\n%s\n' "${calls}" >&2
    return 1
  fi
}

# Every recorded call had the line $1 in its environment.
every_call_had() {
  local environment
  for environment in "${RECORD_DIR}"/env.*; do
    if ! grep -qxF -- "$1" "${environment}"; then
      echo "${environment} has no line $1" >&2
      return 1
    fi
  done
}

# No recorded call had the variable $1 in its environment.
no_call_had() {
  if grep -q "^$1=" "${RECORD_DIR}"/env.*; then
    echo "a zypper call had $1 in its environment" >&2
    return 1
  fi
}

# Every recorded call ran in the environment that the assignments given produce in a shell that runs no installer:
# the feature added, changed, and removed no variable. Left out are _ and SHLVL, which every shell sets for itself.
every_call_had_the_environment_of() {
  local environment expected
  expected="$(env PATH="${RECORDER_PATH}" "$@" /bin/sh -c env | grep -Ev '^(_|SHLVL)=' | sort)"
  for environment in "${RECORD_DIR}"/env.*; do
    if [[ "$(grep -Ev '^(_|SHLVL)=' "${environment}" | sort)" != "${expected}" ]]; then
      echo "${environment} differs from the environment given to install.sh in these lines:" >&2
      comm -3 <(grep -Ev '^(_|SHLVL)=' "${environment}" | sort) <(printf '%s\n' "${expected}") >&2
      return 1
    fi
  done
}

# While every recorded call ran, the feature's temporary configuration files held exactly the text $1.
every_call_saw_the_override() {
  local call
  for call in "${RECORD_DIR}"/env.*; do
    call="${call##*.}"
    if [[ ! -e "${RECORD_DIR}/override.${call}" || "$(<"${RECORD_DIR}/override.${call}")" != "$1" ]]; then
      echo "call ${call} did not see the configuration file with: $1" >&2
      return 1
    fi
  done
}

# While no recorded call ran did /run/zypp exist.
no_call_saw_run_zypp() {
  local marker
  for marker in "${RECORD_DIR}"/run-zypp.*; do
    if [[ -e "${marker}" ]]; then
      echo "/run/zypp existed during a zypper call" >&2
      return 1
    fi
  done
}

# The commands the installer runs beside zypper, mktemp before the first zypper call and rm after the last one, each
# ran and had the line $1 in its environment.
other_commands_had() {
  local command
  for command in mktemp rm; do
    if ! grep -qxF -- "$1" "${RECORD_DIR}/${command}-env"; then
      echo "${command} did not run with the line $1 in its environment" >&2
      return 1
    fi
  done
}

# mktemp and rm each ran, and neither had the variable $1 in its environment.
other_commands_had_no() {
  local command
  for command in mktemp rm; do
    if [[ ! -e "${RECORD_DIR}/${command}-env" ]]; then
      echo "${command} did not run" >&2
      return 1
    fi
    if grep -q "^$1=" "${RECORD_DIR}/${command}-env"; then
      echo "${command} had $1 in its environment" >&2
      return 1
    fi
  done
}

# Runs install.sh like run_recorded, with a stand-in whose calls of the zypper command $1 fail.
run_recorded_failing() {
  rm -rf "${RECORD_DIR}"
  mkdir "${RECORD_DIR}"
  echo "$1" >"${RECORD_DIR}/fail-on"
  run_install PATH="${RECORDER_PATH}" "${@:2}"
}

mkdir /tmp/recorder
install -m 0755 "$(dirname "$0")/zypper_recorder.sh" /tmp/recorder/zypper
# The installer runs mktemp for its temporary file, before the first zypper call of these runs, and rm when it exits,
# after the last one.
for command in mktemp rm; do
  printf '#!/bin/sh\nenv >%s/%s-env\nexec /usr/bin/%s "$@"\n' "${RECORD_DIR}" "${command}" "${command}" \
    >"/tmp/recorder/${command}"
  chmod +x "/tmp/recorder/${command}"
done
configuration_before="$(libzypp_configuration)"

run_recorded PACKAGES=bc
check "with every option omitted the feature succeeds" exited_with 0
check "with every option omitted the feature makes the zypper calls of version 1.0.1" calls_are "${DEFAULT_CALLS}"
check "with every option omitted the calls run in the environment the feature was given" \
  every_call_had_the_environment_of PACKAGES=bc
check "with every option omitted no directory or file of the feature exists at any call" no_call_saw_run_zypp

run_recorded PACKAGES=bc EXACTNAMES=false REPOSITORIES=$' ,\t, ' LOCKTIMEOUT="" CONNECTTIMEOUT="" TRANSFERTIMEOUT="" \
  DOWNLOADRETRIES=""
check "exactNames=false, repositories of separators, and empty timeouts and retries make the same calls" \
  calls_are "${DEFAULT_CALLS}"
check "with those values no directory or file of the feature exists at any call" no_call_saw_run_zypp
check "with those values no call gets a lock wait" no_call_had ZYPP_LOCK_TIMEOUT

run_recorded PACKAGES=bc,file INSTALLRECOMMENDS=true REFRESHPOLICY=always CLEANUP=packages EXACTNAMES=true
check "exactNames=true adds --name to the install call and nothing to the others" calls_are "--non-interactive refresh
--non-interactive --no-refresh install --recommends --name -- bc file
--non-interactive clean"

run_recorded PACKAGES=bc ZYPP_LOCK_TIMEOUT=7
check "with an empty lockTimeout a lock wait of the build environment reaches every call" \
  every_call_had ZYPP_LOCK_TIMEOUT=7
check "with an empty lockTimeout the calls run in the environment the feature was given" \
  every_call_had_the_environment_of PACKAGES=bc ZYPP_LOCK_TIMEOUT=7

run_recorded PACKAGES=bc LOCKTIMEOUT=1 CONNECTTIMEOUT=5
check "lockTimeout=1, the lowest value, succeeds" exited_with 0
check "lockTimeout=1 makes the calls of the default run" calls_are "${DEFAULT_CALLS}"
check "lockTimeout=1 reaches the refresh, the installation, and the cleanup call" every_call_had ZYPP_LOCK_TIMEOUT=1
check "lockTimeout=1 reaches no other command the feature runs, before or after the zypper calls" \
  other_commands_had_no ZYPP_LOCK_TIMEOUT

run_recorded PACKAGES=bc LOCKTIMEOUT=3600 CONNECTTIMEOUT=5 ZYPP_LOCK_TIMEOUT=7
check "lockTimeout=3600, the highest value, succeeds" exited_with 0
check "lockTimeout=3600 overrides the lock wait of the build environment on every call" \
  every_call_had ZYPP_LOCK_TIMEOUT=3600
check "the other commands the feature runs, before and after the zypper calls, have the build environment's lock wait" \
  other_commands_had ZYPP_LOCK_TIMEOUT=7

run_recorded PACKAGES=bc CONNECTTIMEOUT=1 TRANSFERTIMEOUT=3600 DOWNLOADRETRIES=10
check "connectTimeout=1, transferTimeout=3600, and downloadRetries=10, each a bound, succeed" exited_with 0
check "the three options make the calls of the default run" calls_are "${DEFAULT_CALLS}"
check "the file sets the three keys, retries plus one as the attempts, and nothing else, at every call" \
  every_call_saw_the_override "[main]
download.connect_timeout = 1
download.transfer_timeout = 3600
download.max_silent_tries = 11"
check "the three options leave the rest of the environment as the feature was given it" \
  every_call_had_the_environment_of PACKAGES=bc CONNECTTIMEOUT=1 TRANSFERTIMEOUT=3600 DOWNLOADRETRIES=10
check "after the successful run neither the file nor a directory of the feature exists" no_override_left

run_recorded PACKAGES=bc CONNECTTIMEOUT=3600
check "connectTimeout=3600, the highest value, succeeds" exited_with 0
check "connectTimeout alone writes only its key: the transfer timeout stays the image's" \
  every_call_saw_the_override "[main]
download.connect_timeout = 3600"

run_recorded PACKAGES=bc TRANSFERTIMEOUT=1
check "transferTimeout=1, the lowest value, succeeds" exited_with 0
check "transferTimeout alone writes only its key: the connect timeout stays the image's" \
  every_call_saw_the_override "[main]
download.transfer_timeout = 1"

run_recorded PACKAGES=bc DOWNLOADRETRIES=0
check "downloadRetries=0, the lowest value, succeeds" exited_with 0
check "downloadRetries=0 writes one attempt and no other key" every_call_saw_the_override "[main]
download.max_silent_tries = 1"

run_recorded_failing install PACKAGES=bc TRANSFERTIMEOUT=30 DOWNLOADRETRIES=3
check "a failing installation fails the feature" failed
check "with downloadRetries=3 the failing installation is called once, and no cleanup follows" \
  calls_are "--non-interactive refresh
--non-interactive --no-refresh install --no-recommends -- bc"
check "the failing installation saw the file" every_call_saw_the_override "[main]
download.transfer_timeout = 30
download.max_silent_tries = 4"
check "after the failing run neither the file nor a directory of the feature exists" no_override_left

run_recorded_failing refresh PACKAGES=bc DOWNLOADRETRIES=3
check "a failing refresh fails the feature" failed
check "with downloadRetries=3 the failing refresh is called once, and nothing follows" \
  calls_are "--non-interactive refresh"
check "after the failing refresh neither the file nor a directory of the feature exists" no_override_left

# A selection begins with zypper's listing of the repositories, which can download: the file is there for that call
# too. The stand-in lists no repository, so the alias is refused, and the file goes with the failed run.
run_recorded PACKAGES=bc REPOSITORIES=repo-oss CONNECTTIMEOUT=5 DOWNLOADRETRIES=2
check "with a selection the feature lists the repositories first" \
  calls_are "--xmlout --non-interactive --no-refresh repos"
check "the listing of a selection, the feature's first zypper call, saw the file" every_call_saw_the_override "[main]
download.connect_timeout = 5
download.max_silent_tries = 3"
check "an alias the listing does not hold fails with status 1" exited_with 1
check "after the refused alias neither the file nor a directory of the feature exists" no_override_left

# An image that has the directory already, with a file of its own in it: the feature removes only what it created.
mkdir -p /run/zypp/zypp.conf.d
echo keep >/run/zypp/zypp.conf.d/image-file
directory_before="$(libzypp_configuration)"
run_recorded PACKAGES=bc CONNECTTIMEOUT=30
check "with an existing directory the feature succeeds" exited_with 0
check "with an existing directory the calls see the feature's file" every_call_saw_the_override "[main]
download.connect_timeout = 30"
check "the existing directory and the image's file in it are as before" libzypp_configuration_is "${directory_before}"
rm -r /run/zypp

printf '[main]\n' >"${ZYPP_CONF_FILE}"
for zypp_conf in "${ZYPP_CONF_FILE}" /tmp/no-such-zypp.conf ""; do
  # Each entry is "<option> <environment assignment>".
  for override in "connectTimeout CONNECTTIMEOUT=30" "transferTimeout TRANSFERTIMEOUT=30" \
    "downloadRetries DOWNLOADRETRIES=2"; do
    option="${override%% *}"
    run_recorded PACKAGES=bc ZYPP_CONF="${zypp_conf}" "${override#* }"
    check "with ZYPP_CONF='${zypp_conf}', ${option} fails with status 1" exited_with 1
    check "with ZYPP_CONF='${zypp_conf}', the message of ${option} names ZYPP_CONF" printed "ZYPP_CONF"
    check "with ZYPP_CONF='${zypp_conf}', the message of ${option} names the option" printed "${option}"
    check "with ZYPP_CONF='${zypp_conf}', ${option} calls no zypper" calls_are ""
  done
  run_recorded PACKAGES=bc ZYPP_CONF="${zypp_conf}" LOCKTIMEOUT=5 EXACTNAMES=true
  check "with ZYPP_CONF='${zypp_conf}' and no timeout or retry option the feature succeeds" exited_with 0
  check "with ZYPP_CONF='${zypp_conf}' every call gets the variable unchanged" every_call_had "ZYPP_CONF=${zypp_conf}"
done

check "no run left anything of a temporary configuration file" no_override_left
check "the directories libzypp reads configuration from are as before the runs" \
  libzypp_configuration_is "${configuration_before}"

reportResults
