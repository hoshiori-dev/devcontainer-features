#!/usr/bin/env bash
# Stands in for curl in the fail_contract scenario: answers the installer's requests from local fixtures, records each
# request, and rejects any request made without the HTTPS-only flags for the request and its redirects.
set -euo pipefail

output=""
url=""
proto=""
proto_redir=""
arguments="$*"
while (($# > 0)); do
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
    --retry | --header) shift 2 ;;
    --location | --fail | --silent | --show-error) shift ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "${url}" >>"${FIXTURE_DIR}/requests"
printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/arguments"
if [[ "${proto}" != "=https" || "${proto_redir}" != "=https" ]]; then
  printf 'fixture curl: request without --proto =https --proto-redir =https: %s\n' "${arguments}" >&2
  exit 99
fi
mode="$(cat "${FIXTURE_DIR}/mode")"
if [[ "${mode}" == network ]]; then
  printf 'curl: (6) Could not resolve host: %s\n' "${url}" >&2
  exit 6
fi
# Answers an HTTP error status the way curl --fail does.
http_error() {
  printf 'curl: (22) The requested URL returned error: %s\n' "$1" >&2
  exit 22
}
readonly API="https://api.github.com/repos/FreeCAD/FreeCAD/releases"
readonly DOWNLOAD="https://github.com/FreeCAD/FreeCAD/releases/download"
case "${url}" in
  "${API}"*)
    # GitHub answers an unauthenticated client over its rate limit with 403.
    if [[ "${mode}" == rate_limit ]]; then http_error 403; fi
    case "${url}" in
      "${API}/latest") source_file="${FIXTURE_DIR}/api/latest.json" ;;
      "${API}/tags/"*) source_file="${FIXTURE_DIR}/api/tags/${url##*/}.json" ;;
      "${API}?per_page=100&page="*) source_file="${FIXTURE_DIR}/api/page${url##*=}.json" ;;
      *)
        printf 'fixture curl: unexpected API URL %s\n' "${url}" >&2
        exit 1
        ;;
    esac
    [[ -f "${source_file}" ]] || http_error 404
    cp "${source_file}" "${output}"
    ;;
  "${DOWNLOAD}/"*/*.AppImage)
    source_file="${FIXTURE_DIR}/releases/${url#"${DOWNLOAD}/"}"
    [[ -f "${source_file}" ]] || http_error 404
    cp "${source_file}" "${output}"
    if [[ "${mode}" == corrupt ]]; then printf '\n# corrupt\n' >>"${output}"; fi
    ;;
  "${DOWNLOAD}/"*/*.AppImage-SHA256.txt)
    source_file="${FIXTURE_DIR}/releases/${url#"${DOWNLOAD}/"}"
    if [[ "${mode}" == missing_checksum || ! -f "${source_file}" ]]; then http_error 404; fi
    case "${mode}" in
      missing_entry) printf '%s  another-file\n' "$(printf other | sha256sum | cut -d ' ' -f 1)" >"${output}" ;;
      duplicate) cat "${source_file}" "${source_file}" >"${output}" ;;
      *) cp "${source_file}" "${output}" ;;
    esac
    ;;
  *)
    printf 'fixture curl: unexpected URL %s\n' "${url}" >&2
    exit 1
    ;;
esac
