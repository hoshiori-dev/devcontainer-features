#!/bin/sh
# Stands in for curl in the fail_contract scenario: records each request and its arguments, rejects a request made
# without the HTTPS-only, no-redirect, fail-on-error flags, and answers from ${FIXTURE_DIR}/serve/<host>/<path>. A
# missing file answers like a 404; a file named <path>.redirect answers like a redirect refused by --max-redirs 0.
set -eu

output=""
url=""
proto=""
max_redirs=""
location=false
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
    --max-redirs)
      max_redirs="$2"
      shift 2
      ;;
    --retry) shift 2 ;;
    --location)
      location=true
      shift
      ;;
    --fail)
      fail_flag=true
      shift
      ;;
    --silent | --show-error) shift ;;
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
if [ "${proto}" != "=https" ] || [ "${max_redirs}" != "0" ] || [ "${location}" != "true" ] \
  || [ "${fail_flag}" != "true" ]; then
  printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/violations"
  echo 'curl stand-in: a request without --proto =https, --location, --max-redirs 0, and --fail' >&2
  exit 2
fi

path="${FIXTURE_DIR}/serve/${url#https://}"
if [ -f "${path}.redirect" ]; then
  echo 'curl: (47) Maximum (0) redirects followed' >&2
  exit 47
fi
if [ ! -f "${path}" ]; then
  echo 'curl: (22) The requested URL returned error: 404' >&2
  exit 22
fi
if [ -n "${output}" ]; then
  cp "${path}" "${output}"
else
  cat "${path}"
fi
