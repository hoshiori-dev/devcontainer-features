#!/bin/sh
# Stands in for curl in the fail_install scenario: records each requested URL in ${FIXTURE_DIR}/requests, rejects a
# request made without the HTTPS-only (on every hop) and fail-on-error flags, and answers from
# ${FIXTURE_DIR}/serve/<host>/<path> when that file exists: a file named <path>.missing answers like a 404, and a
# HEAD request that asks for the redirect URL prints the content of <path>.location. Every other request goes to the
# real curl with the same arguments.
set -eu

readonly REAL_CURL="/usr/bin/curl"

output=""
url=""
proto=""
proto_redir=""
write_out=""
head=false
fail_flag=false
for argument in "$@"; do
  case "${previous-}" in
    --output) output="${argument}" ;;
    --proto) proto="${argument}" ;;
    --proto-redir) proto_redir="${argument}" ;;
    --write-out) write_out="${argument}" ;;
  esac
  case "${argument}" in
    --head) head=true ;;
    --fail) fail_flag=true ;;
    https://*) url="${argument}" ;;
  esac
  previous="${argument}"
done
printf '%s\n' "${url}" >>"${FIXTURE_DIR}/requests"
if [ "${proto}" != "=https" ] || [ "${proto_redir}" != "=https" ] || [ "${fail_flag}" != "true" ]; then
  printf '%s\n' "$*" >>"${FIXTURE_DIR}/violations"
  echo 'curl stand-in: a request without --proto =https, --proto-redir =https, and --fail' >&2
  exit 2
fi

path="${FIXTURE_DIR}/serve/${url#https://}"
if [ -f "${path}.missing" ]; then
  echo 'curl: (22) The requested URL returned error: 404' >&2
  exit 22
fi
if [ "${head}" = "true" ] && [ "${write_out}" = "%{redirect_url}" ] && [ -f "${path}.location" ]; then
  cat "${path}.location"
  exit 0
fi
if [ -f "${path}" ]; then
  if [ -n "${output}" ]; then
    cp "${path}" "${output}"
  else
    cat "${path}"
  fi
  exit 0
fi
exec "${REAL_CURL}" "$@"
