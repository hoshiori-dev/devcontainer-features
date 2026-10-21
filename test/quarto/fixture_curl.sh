#!/usr/bin/env bash
# Replaces network responses with local release fixtures for installer failure scenarios.
set -euo pipefail
output=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --proto | --proto-redir | --retry) shift 2 ;;
    --fail | --silent | --show-error | --location) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "${url}" >>"${FIXTURE_DIR}/requests"
mode="$(cat "${FIXTURE_DIR}/mode")"
if [[ "${mode}" == network ]]; then exit 22; fi
case "${url}" in
  https://api.github.com/repos/quarto-dev/quarto-cli/releases/*)
    version="${url##*/v}"
    if [[ "${url}" == */latest ]]; then version="$(cat "${FIXTURE_DIR}/latest")"; fi
    prerelease=false
    if [[ "${mode}" == prerelease ]]; then prerelease=true; fi
    jq -n --arg tag "v${version}" --argjson prerelease "${prerelease}" \
      '{tag_name:$tag, draft:false, prerelease:$prerelease, assets:[
        {name:("quarto-" + ($tag|ltrimstr("v")) + "-linux-amd64.tar.gz")},
        {name:("quarto-" + ($tag|ltrimstr("v")) + "-linux-arm64.tar.gz")}]}' >"${output}"
    if [[ "${mode}" == metadata ]]; then printf '{' >"${output}"; fi
    if [[ "${mode}" == missing_asset ]]; then
      jq '.assets = []' "${output}" >"${output}.tmp"
      mv "${output}.tmp" "${output}"
    fi
    ;;
  https://github.com/quarto-dev/quarto-cli/releases/download/*)
    name="${url##*/}"
    parent="${url%/*}"
    version="${parent##*/v}"
    case "${name}" in
      *checksums.txt)
        if [[ "${mode}" == missing_checksum ]]; then exit 22; fi
        cp "${FIXTURE_DIR}/${version}/checksums.txt" "${output}"
        if [[ "${mode}" == duplicate ]]; then cat "${FIXTURE_DIR}/${version}/checksums.txt" >>"${output}"; fi
        if [[ "${mode}" == missing_entry ]]; then printf '' >"${output}"; fi
        ;;
      *.tar.gz)
        cp "${FIXTURE_DIR}/${version}/archive.tar.gz" "${output}"
        if [[ "${mode}" == corrupt ]]; then printf corrupt >>"${output}"; fi
        ;;
      *) exit 22 ;;
    esac
    ;;
  *) printf 'unexpected URL %s\n' "${url}" >&2; exit 1 ;;
esac
