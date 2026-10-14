#!/usr/bin/env bash
# Scenario fail_refused_controls_0 (scenarios.json): the container has no network, the feature is installed with an
# empty list, and this script runs install.sh with values of exactNames, repositories, lockTimeout, connectTimeout,
# transferTimeout, and downloadRetries that validation refuses, with an empty list and with the list bc, and with valid
# values beside an empty list. zypper is a stand-in that records its calls (zypper_recorder.sh). Spec scenarios "Invalid
# control fails before any change", "Lock timeout boundaries are validated", "Connect timeout boundaries are validated",
# "Transfer timeout boundaries are validated", "Retry boundaries are validated", "Malformed repository alias is
# refused", "Empty list ignores installation controls", "Empty list ignores selection and network controls", and "Only
# separators in repositories" with an empty list.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly RECORD_DIR="/tmp/zypper-record"
# A PATH on which zypper is the recording stand-in.
readonly RECORDER_PATH="/tmp/recorder:/usr/sbin:/usr/bin:/sbin:/bin"
# A PATH that holds no command at all, so no zypper either.
readonly NO_ZYPPER_PATH="/tmp/no-manager"

# Each entry is "<option> <environment variable> <lowest value> <highest value> <one above the highest>".
readonly NUMERIC_OPTIONS=(
  "lockTimeout LOCKTIMEOUT 1 3600 3601"
  "connectTimeout CONNECTTIMEOUT 1 3600 3601"
  "transferTimeout TRANSFERTIMEOUT 1 3600 3601"
  "downloadRetries DOWNLOADRETRIES 0 10 11"
)

# Values no numeric option accepts: a sign, a leading zero, a number followed by a letter, whitespace, a fraction, shell
# text, a number too long for the shell's arithmetic, and a line break followed by a configuration key.
readonly INVALID_NUMBERS=(
  "-1" "+5" "05" "00" "4x" " 5" "5 " "1.5" "\$(id)" "5;id" "99999999999999999999" $'5\ngpgcheck = 0'
)

# Items repositories refuses: a number, a URI, a path, a glob, an option, whitespace inside, and a character outside
# the accepted set.
readonly MALFORMED_ALIASES=(
  "12" "http://example.invalid/repo" "dir:/tmp/repo" "/etc/zypp/repos.d" "repo-*" "repo-?ss" "-repo"
  "--plus-content" "repo oss" "repo@oss" "repo=oss" ".repo" "répo"
)

# The assignment $2 fails with status 1, naming the option $1, with the package list $3.
refuses_control() {
  run_install PATH="${RECORDER_PATH}" PACKAGES="$3" "$2"
  exited_with 1 && printed "option $1"
}

# The item $1 of repositories fails with status 1, naming repositories and the item, with the package list $2. A
# well-formed alias stands beside it, so a gap in the validation would reach zypper.
refuses_alias() {
  run_install PATH="${RECORDER_PATH}" PACKAGES="$2" REPOSITORIES="repo-oss, $1"
  exited_with 1 && printed "option repositories" && printed "'$1'"
}

zypper_was_not_called() {
  if [[ -e "${RECORD_DIR}/calls" ]]; then
    echo "zypper was called: $(<"${RECORD_DIR}/calls")" >&2
    return 1
  fi
}

mkdir /tmp/recorder "${NO_ZYPPER_PATH}"
install -m 0755 "$(dirname "$0")/zypper_recorder.sh" /tmp/recorder/zypper
database_before="$(rpm_database)"
configuration_before="$(libzypp_configuration)"

for value in yes TRUE 1 ""; do
  check "exactNames '${value}' fails with status 1 and names exactNames, with an empty list" \
    refuses_control exactNames "EXACTNAMES=${value}" ""
  check "exactNames '${value}' fails with status 1 and names exactNames, with the list bc" \
    refuses_control exactNames "EXACTNAMES=${value}" "bc"
done

for numeric_option in "${NUMERIC_OPTIONS[@]}"; do
  read -r option variable lowest highest above <<<"${numeric_option}"
  invalid=("${INVALID_NUMBERS[@]}" "${above}")
  # Zero is the lowest value of downloadRetries and below the lowest of the three timeouts.
  if [[ "${lowest}" -ne 0 ]]; then invalid+=("0"); fi
  for value in "${invalid[@]}"; do
    check "${option} '${value}' fails with status 1 and names ${option}, with an empty list" \
      refuses_control "${option}" "${variable}=${value}" ""
    check "${option} '${value}' fails with status 1 and names ${option}, with the list bc" \
      refuses_control "${option}" "${variable}=${value}" "bc"
  done
  for value in "" "${lowest}" "${highest}"; do
    run_install PATH="${RECORDER_PATH}" PACKAGES="" "${variable}=${value}"
    check "${option} '${value}' is accepted with an empty list" exited_with 0
  done
done

for alias in "${MALFORMED_ALIASES[@]}"; do
  check "the repositories item '${alias}' fails with status 1 and is named, with an empty list" \
    refuses_alias "${alias}" ""
  check "the repositories item '${alias}' fails with status 1 and is named, with the list bc" \
    refuses_alias "${alias}" "bc"
done

run_install PATH="${RECORDER_PATH}" PACKAGES="" REPOSITORIES=$' ,\t, '
check "repositories of commas and whitespace succeeds with an empty list" exited_with 0

# Valid controls beside an empty list: an alias no repository has, timeouts and retries that could not take effect
# with ZYPP_CONF set, and no check of either.
for zypp_conf in /tmp/no-such-zypp.conf ""; do
  run_install PATH="${RECORDER_PATH}" PACKAGES=" , " EXACTNAMES=true REPOSITORIES=no-such-repository LOCKTIMEOUT=5 \
    CONNECTTIMEOUT=5 TRANSFERTIMEOUT=5 DOWNLOADRETRIES=2 ZYPP_CONF="${zypp_conf}"
  check "an empty list succeeds with an unknown alias, timeouts, retries, and ZYPP_CONF='${zypp_conf}'" exited_with 0
done
run_install PATH="${NO_ZYPPER_PATH}" PACKAGES="" EXACTNAMES=true REPOSITORIES=no-such-repository LOCKTIMEOUT=5 \
  CONNECTTIMEOUT=5 TRANSFERTIMEOUT=5 DOWNLOADRETRIES=2 ZYPP_CONF=/tmp/no-such-zypp.conf
check "the same empty list succeeds without zypper, and without any other command, on PATH" exited_with 0

check "no run called zypper" zypper_was_not_called
check "no run wrote a file: the directories libzypp reads configuration from are unchanged" \
  libzypp_configuration_is "${configuration_before}"
check "no run left anything of a temporary configuration file" no_override_left
check "no run loaded metadata" no_metadata
check "no run downloaded metadata" no_raw_metadata
check "no run changed an installed package" rpm_database_is "${database_before}"

reportResults
