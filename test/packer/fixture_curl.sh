#!/bin/sh
# Stands in for curl in the fail_contract scenario: records each request and its arguments, rejects a request made
# without the HTTPS-only and fail-on-error flags or with a redirect-following one, and answers from
# ${FIXTURE_DIR}/serve/<host>/<path>. A missing file answers like a 404. A file <path>.status makes the request answer
# with that HTTP status and the body "redirect", as a real curl does for a redirect it does not follow.
set -eu

output=""
url=""
proto=""
write_out=""
fail_flag=false
arguments="$*"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output="$2"
      shift 2
      ;;
    --proto)
      proto="$2"
      shift 2
      ;;
    --write-out)
      write_out="$2"
      shift 2
      ;;
    --retry) shift 2 ;;
    --fail)
      fail_flag=true
      shift
      ;;
    --silent | --show-error) shift ;;
    # Any other option is a violation, --location and --proto-redir among them: no request may follow a redirect.
    -*)
      printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/violations"
      printf 'curl stand-in: unexpected option %s\n' "$1" >&2
      exit 2
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "${url}" >>"${FIXTURE_DIR}/requests"
if [ "${proto}" != "=https" ] || [ "${fail_flag}" != "true" ] || [ -z "${output}" ] \
  || [ "${write_out}" != "%{http_code}" ]; then
  printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/violations"
  echo 'curl stand-in: a request without --proto =https, --fail, --output, and --write-out %{http_code}' >&2
  exit 2
fi

path="${FIXTURE_DIR}/serve/${url#https://}"
if [ -f "${path}.status" ]; then
  echo redirect >"${output}"
  cat "${path}.status"
  exit 0
fi
if [ ! -f "${path}" ]; then
  echo 'curl: (22) The requested URL returned error: 404' >&2
  printf 404
  exit 22
fi
cp "${path}" "${output}"
printf 200
