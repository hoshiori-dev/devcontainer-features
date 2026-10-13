#!/bin/sh
# Stand-in for zypper that the scenario scripts put first on PATH as `zypper`, to see how install.sh calls it. Each
# call is recorded under /tmp/zypper-record: its arguments as one line of `calls`, and under the number of that line
# its environment (`env.<n>`), the content of the feature's temporary configuration files while they exist
# (`override.<n>`), and whether /run/zypp exists (`run-zypp.<n>`). What the call then does is the script's choice:
# with a file `real` in that directory it runs the image's zypper, otherwise it prints nothing and succeeds, and a
# file `fail-on` holding a zypper command, such as install, makes the calls of that command exit with status 4.
set -eu

readonly RECORD_DIR="/tmp/zypper-record"

mkdir -p "${RECORD_DIR}"
printf '%s\n' "$*" >>"${RECORD_DIR}/calls"
call="$(grep -c '' "${RECORD_DIR}/calls")"
env >"${RECORD_DIR}/env.${call}"
if [ -e /run/zypp ]; then echo exists >"${RECORD_DIR}/run-zypp.${call}"; fi
for file in /run/zypp/zypp.conf.d/*.conf; do
  if [ -f "${file}" ]; then cat "${file}" >>"${RECORD_DIR}/override.${call}"; fi
done

if [ -f "${RECORD_DIR}/fail-on" ]; then
  fail_on="$(cat "${RECORD_DIR}/fail-on")"
  for argument in "$@"; do
    if [ "${argument}" = "${fail_on}" ]; then exit 4; fi
  done
fi
if [ -f "${RECORD_DIR}/real" ]; then exec /usr/bin/zypper "$@"; fi
