#!/bin/sh
# Stands in for curl in the fail_contract scenario: records each request and its arguments, rejects a request made
# without the HTTPS-only (on every hop) and fail-on-error flags, and answers from ${FIXTURE_DIR}/serve/<host>/<path>. A
# missing file answers like a 404. A HEAD request that asks for the redirect URL prints the content of
# <path>.location, or nothing when only <path> exists.
set -eu

output=""
url=""
proto=""
proto_redir=""
write_out=""
head=false
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
    --proto-redir)
      proto_redir="$2"
      shift 2
      ;;
    --write-out)
      write_out="$2"
      shift 2
      ;;
    --retry) shift 2 ;;
    --head)
      head=true
      shift
      ;;
    --fail)
      fail_flag=true
      shift
      ;;
    --location | --silent | --show-error) shift ;;
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
if [ "${proto}" != "=https" ] || [ "${proto_redir}" != "=https" ] || [ "${fail_flag}" != "true" ]; then
  printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/violations"
  echo 'curl stand-in: a request without --proto =https, --proto-redir =https, and --fail' >&2
  exit 2
fi

path="${FIXTURE_DIR}/serve/${url#https://}"
if [ "${head}" = "true" ] && [ "${write_out}" = "%{redirect_url}" ]; then
  if [ -f "${path}.location" ]; then
    cat "${path}.location"
  elif [ ! -f "${path}" ]; then
    echo 'curl: (22) The requested URL returned error: 404' >&2
    exit 22
  fi
  exit 0
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
if [ "${write_out}" = "%{url_effective}" ]; then printf '%s' "${url}"; fi
