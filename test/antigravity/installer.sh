# shellcheck shell=bash
# Sourced by the antigravity scenario scripts that run install.sh themselves (.agents/knowledge/testing.md, Running the
# installer). A curl stub serves a local manifest and archive, so these runs reach no Google service. This file holds
# the run and the fixtures several scripts use.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER

install_status=0
install_output=""

# Writes a curl stub to directory $1 that serves $ANTIGRAVITY_TEST_MANIFEST for the manifest URL and
# $ANTIGRAVITY_TEST_ARCHIVE for any other URL; an empty manifest path makes the manifest unreachable.
make_curl_stub() {
  mkdir -p "$1"
  cat >"$1/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
output=""
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
case "${url}" in
  */manifests/*.json)
    if [[ -z "${ANTIGRAVITY_TEST_MANIFEST}" ]]; then exit 22; fi
    cp "${ANTIGRAVITY_TEST_MANIFEST}" "${output}"
    ;;
  *) cp "${ANTIGRAVITY_TEST_ARCHIVE}" "${output}" ;;
esac
STUB
  chmod +x "$1/curl"
}

# Writes archive $1 holding an executable `antigravity` whose body is the shell command $2.
make_archive() {
  local directory
  directory="$(mktemp -d)"
  printf '#!/bin/sh\n%s\n' "$2" >"${directory}/antigravity"
  chmod +x "${directory}/antigravity"
  tar -czf "$1" -C "${directory}" antigravity
  rm -r "${directory}"
}

# Writes manifest $1 naming version $2, URL $3, and the SHA-512 of file $4 (or the literal digest $4 if no such file).
make_manifest() {
  local digest="$4"
  if [[ -f "$4" ]]; then digest="$(sha512sum "$4" | cut -d ' ' -f 1)"; fi
  jq -n --arg version "$2" --arg url "$3" --arg sha512 "${digest}" '{version: $version, url: $url, sha512: $sha512}' \
    >"$1"
}

# Runs install.sh as root with PATH starting at directory $1, manifest $2, and archive $3, as the remote user.
run_install() {
  install_status=0
  install_output="$(sudo env PATH="$1:${PATH}" ANTIGRAVITY_TEST_MANIFEST="$2" ANTIGRAVITY_TEST_ARCHIVE="$3" \
    _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)" || install_status=$?
}

# The last run failed and reported error $1.
failed_with() {
  if [[ "${install_status}" -eq 0 || "${install_output}" != *"antigravity: error: $1"* ]]; then
    printf 'install.sh exited with %s:\n%s\n' "${install_status}" "${install_output}" >&2
    return 1
  fi
}

# The last run succeeded and, when $1 is given, reported $1.
succeeded() {
  if [[ "${install_status}" -ne 0 || "${install_output}" != *"${1-}"* ]]; then
    printf 'install.sh exited with %s:\n%s\n' "${install_status}" "${install_output}" >&2
    return 1
  fi
}
