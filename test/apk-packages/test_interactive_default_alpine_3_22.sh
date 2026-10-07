#!/bin/sh
# Scenario test_interactive_default_alpine_3_22 (scenarios.json): the scenario's Dockerfile adds the script command,
# which this script uses to run apk and install.sh with a terminal attached and no input. Spec scenario "Interactive
# default is overridden".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly NO_INPUT="/tmp/no-input"
readonly PREMISE_LOG="/tmp/premise-output"
# A question apk asked cannot hang the test: a run that has not ended by then is stopped and counts as failed.
readonly INSTALL_TIMEOUT_SECONDS=600

apk_asked() {
  grep -Fq '[Y/n]' "${PREMISE_LOG}"
}

# The last run printed no question.
asked_no_question() {
  if output_matches '\[Y/n\]|Do you want to continue'; then
    echo "the feature's apk asked a question" >&2
    return 1
  fi
}

touch /etc/apk/interactive
# A terminal's input that never holds a byte and never ends: a named pipe this script keeps open and never writes to.
mkfifo "${NO_INPUT}"
exec 3<>"${NO_INPUT}"

# With a terminal, apk itself asks on this image and waits. It is stopped as soon as it has asked, or after 120 s.
script -q -c "apk --no-cache add tree" /dev/null <&3 >"${PREMISE_LOG}" 2>&1 &
premise_pid=$!
waited=0
until apk_asked || [ "${waited}" -ge 120 ]; do
  sleep 1
  waited=$((waited + 1))
done
check "premise: with /etc/apk/interactive and a terminal, apk itself asks a question" apk_asked
kill "${premise_pid}"
wait "${premise_pid}" || true
# script has ended; the apk it ran on its terminal ends a moment later and holds the database lock until then.
waited=0
while pidof apk >/dev/null && [ "${waited}" -lt 30 ]; do
  sleep 1
  waited=$((waited + 1))
done
check "premise: apk waited for an answer and did not install tree" not_installed tree

# script runs the feature on a terminal of its own and exits with the feature's status.
record_run timeout "${INSTALL_TIMEOUT_SECONDS}" script -q -e -c "PACKAGES=file '${INSTALLER}'" /dev/null <&3
check "with a terminal attached and no input the feature completes with status 0" exited_with 0
check "the feature's apk asked no question" asked_no_question
check "file is installed" installed file

reportResults
