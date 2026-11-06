#!/usr/bin/env bash
# Stands in for curl in the fail_contract scenario: answers the installer's requests from local fixtures, records each
# request, and rejects any request made without the HTTPS-only, no-redirect flags.
set -euo pipefail

output=""
url=""
proto=""
max_redirs=""
location=false
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
    --max-redirs)
      max_redirs="$2"
      shift 2
      ;;
    --retry) shift 2 ;;
    --location)
      location=true
      shift
      ;;
    --fail | --silent | --show-error) shift ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
printf '%s\n' "${url}" >>"${FIXTURE_DIR}/requests"
printf '%s\n' "${arguments}" >>"${FIXTURE_DIR}/arguments"
if [[ "${proto}" != "=https" || "${max_redirs}" != 0 || "${location}" != true ]]; then
  printf 'fixture curl: request without --proto =https --location --max-redirs 0: %s\n' "${arguments}" >&2
  exit 99
fi
mode="$(cat "${FIXTURE_DIR}/mode")"
case "${mode}" in
  network)
    printf 'curl: (6) Could not resolve host: download.blender.org\n' >&2
    exit 6
    ;;
  redirect)
    printf 'curl: (47) Maximum (0) redirects followed\n' >&2
    exit 47
    ;;
esac
# Answers 404 the way curl --fail does.
not_found() {
  printf 'curl: (22) The requested URL returned error: 404\n' >&2
  exit 22
}
case "${url}" in
  https://download.blender.org/release/)
    cp "${FIXTURE_DIR}/listings/index.html" "${output}"
    ;;
  https://download.blender.org/release/Blender*/)
    series="${url%/}"
    series="${series##*/Blender}"
    [[ -f "${FIXTURE_DIR}/listings/${series}.html" ]] || not_found
    cp "${FIXTURE_DIR}/listings/${series}.html" "${output}"
    ;;
  https://download.blender.org/release/Blender*/blender-*-linux-x64.tar.xz)
    name="${url##*/}"
    release="${name#blender-}"
    release="${release%-linux-x64.tar.xz}"
    [[ -f "${FIXTURE_DIR}/releases/${release}/${name}" ]] || not_found
    cp "${FIXTURE_DIR}/releases/${release}/${name}" "${output}"
    if [[ "${mode}" == corrupt ]]; then printf corrupt >>"${output}"; fi
    ;;
  https://download.blender.org/release/Blender*/blender-*.sha256)
    name="${url##*/}"
    release="${name#blender-}"
    release="${release%.sha256}"
    if [[ "${mode}" == missing_checksum || ! -f "${FIXTURE_DIR}/releases/${release}/${name}" ]]; then not_found; fi
    case "${mode}" in
      missing_entry) grep -v 'linux-x64' "${FIXTURE_DIR}/releases/${release}/${name}" >"${output}" ;;
      duplicate)
        cat "${FIXTURE_DIR}/releases/${release}/${name}" "${FIXTURE_DIR}/releases/${release}/${name}" >"${output}"
        ;;
      *) cp "${FIXTURE_DIR}/releases/${release}/${name}" "${output}" ;;
    esac
    ;;
  *)
    printf 'fixture curl: unexpected URL %s\n' "${url}" >&2
    exit 1
    ;;
esac
