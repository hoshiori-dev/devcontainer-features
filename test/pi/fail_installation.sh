#!/usr/bin/env bash
# Runs the installer against invalid options, uncovered platforms, conflicting paths, and release fixtures served by a
# curl stub, and checks that every rejection leaves the installed CLI in place.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
before="$(pi --version)"
readonly before
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Runs the installer as root with VERSION=$1 and extra PATH directory $2, and succeeds when it fails with an error
# message containing $3.
rejects() {
  local version="$1" directory="$2" expected="$3" output
  if output="$(sudo env PATH="${directory:+${directory}:}${PATH}" VERSION="${version}" \
    PI_TEST_CASE="${case_name-}" PI_TEST_DIR="${work}" _REMOTE_USER="$(id -un)" \
    _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"; then
    printf '%s\n' "${output}"
    return 1
  fi
  [[ "${output}" == *"pi: error: "*"${expected}"* ]] || { printf '%s\n' "${output}"; return 1; }
}

# This literal shell syntax must reach option validation without expansion.
# shellcheck disable=SC2016
for version in "" v1.4.0 1.4.0-beta.1 1.4 '$(touch /tmp/pi-option-executed)'; do
  check "a malformed or prerelease version is rejected: ${version}" rejects "${version}" "" "option version is"
done
check "version input is never evaluated as shell code" test ! -e /tmp/pi-option-executed
for version in 1.2.0 0.99.2; do
  check "a release below 1.3.0 is rejected: ${version}" rejects "${version}" "" "supports Pi 1.3.0 and newer"
done
check "an unpublished release is rejected" rejects 1.999.0 "" "cannot read release 1.999.0"

mkdir "${work}/system" "${work}/cpu" "${work}/musl"
printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"${work}/system/uname"
cat >"${work}/cpu/uname" <<'STUB'
#!/bin/sh
case "$1" in --kernel-name) printf 'Linux\n' ;; *) printf 'mips\n' ;; esac
STUB
printf '#!/bin/sh\nprintf "musl libc (x86_64)\\nVersion 1.2.5\\n" >&2\nexit 1\n' >"${work}/musl/ldd"
chmod +x "${work}/system/uname" "${work}/cpu/uname" "${work}/musl/ldd"
check "an uncovered system is rejected" rejects 1.4.0 "${work}/system" "unsupported system"
check "an uncovered CPU is rejected" rejects 1.4.0 "${work}/cpu" "unsupported architecture"
check "a musl system is rejected without another installation route" rejects 1.4.0 "${work}/musl" \
  "unsupported C library musl"

# Builds release archive fixture $1.tar.gz whose pi/pi runs the shell command $2.
make_archive() {
  mkdir -p "${work}/$1/pi"
  printf '#!/bin/sh\n%s\n' "$2" >"${work}/$1/pi/pi"
  chmod +x "${work}/$1/pi/pi"
  printf '{"name":"@earendil-works/pi-coding-agent","version":"1.4.0"}\n' >"${work}/$1/pi/package.json"
  tar -czf "${work}/$1.tar.gz" -C "${work}/$1" pi
}
make_archive broken 'exit 37'
# Reports its release when run directly but not through /usr/local/bin/pi, like an executable that cannot find the
# bundled files beside it.
# shellcheck disable=SC2016
make_archive unlinked 'if [ "$0" = /usr/local/bin/pi ]; then echo 0.0.0; else echo 1.4.0; fi'

# A GitHub stub: PI_TEST_CASE selects the fixture and every requested URL is appended to requests.log.
mkdir "${work}/release"
cat >"${work}/release/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
output=""
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
printf '%s\n' "${url}" >>"${PI_TEST_DIR}/requests.log"
assets='["pi-linux-x64.tar.gz","pi-linux-arm64.tar.gz","SHA256SUMS"]'
release() {
  jq -n --arg tag "$1" --argjson prerelease "$2" --argjson assets "$3" \
    '{tag_name:$tag,draft:false,prerelease:$prerelease,assets:($assets | map({name:.}))}' >"${output}"
}
sums() {
  local sum
  sum="$(sha256sum "${PI_TEST_DIR}/$1.tar.gz" | cut -d ' ' -f 1)"
  printf '%s  %s\n' "${sum}" pi-linux-x64.tar.gz "${sum}" pi-linux-arm64.tar.gz >"${output}"
}
case "${PI_TEST_CASE}:${url}" in
  latest_prerelease:*/releases/latest) release v1.6.0-rc.1 true "${assets}" ;;
  latest_old:*/releases/latest) release v1.2.0 false "${assets}" ;;
  other_tag:*/releases/tags/v1.4.0) release v1.5.0 false "${assets}" ;;
  no_archive:*/releases/tags/v1.4.0) release v1.4.0 false '["SHA256SUMS"]' ;;
  *:*/releases/tags/v1.4.0) release v1.4.0 false "${assets}" ;;
  no_entry:*/SHA256SUMS) printf '%064d  pi-linux-riscv64.tar.gz\n' 0 >"${output}" ;;
  corrupt:*/SHA256SUMS | broken:*/SHA256SUMS) sums broken ;;
  unlinked:*/SHA256SUMS) sums unlinked ;;
  corrupt:*.tar.gz) printf 'corrupt archive\n' >"${output}" ;;
  broken:*.tar.gz | unlinked:*.tar.gz) cp "${PI_TEST_DIR}/${PI_TEST_CASE}.tar.gz" "${output}" ;;
  *) exit 22 ;;
esac
STUB
chmod +x "${work}/release/curl"
no_download_requested() { ! grep -q /releases/download/ "${work}/requests.log"; }

case_name=latest_prerelease
check "a prerelease named latest is rejected" rejects latest "${work}/release" "is not a stable"
case_name=latest_old
check "a latest release below 1.3.0 is rejected" rejects latest "${work}/release" "older than 1.3.0"
check "nothing is downloaded after a rejected release" no_download_requested
case_name=other_tag
check "release metadata naming another tag is rejected" rejects 1.4.0 "${work}/release" \
  "names v1.5.0 for version 1.4.0"
case_name=no_archive
check "a release without the platform archive is rejected" rejects 1.4.0 "${work}/release" "publishes no pi-linux-"
case_name=no_checksums
check "a release whose SHA256SUMS cannot be downloaded is rejected" rejects 1.4.0 "${work}/release" \
  "cannot download SHA256SUMS"
case_name=no_entry
check "a SHA256SUMS without the archive's checksum is rejected" rejects 1.4.0 "${work}/release" \
  "lists no single checksum"
case_name=corrupt
check "an archive that does not match SHA256SUMS is rejected" rejects 1.4.0 "${work}/release" \
  "does not match its SHA256SUMS"
case_name=broken
check "a verified executable that cannot run is rejected" rejects 1.4.0 "${work}/release" "cannot run"
case_name=unlinked
check "an executable that cannot load its bundled files through the link is rolled back" \
  rejects 1.4.0 "${work}/release" "the previous installation is restored"

# The expected archive depends on the test machine's architecture.
archive_target=x64
if [[ "$(uname -m)" == aarch64 ]]; then archive_target=arm64; fi
check "the platform archive follows the system's architecture" grep -qx \
  "https://github.com/earendil-works/pi/releases/download/v1.4.0/pi-linux-${archive_target}.tar.gz" \
  "${work}/requests.log"

# Runs the installer for a home whose ~/.pi/agent is an existing $1 (directory or foreign link).
build_conflict_preserved() {
  local kind="$1" home="${work}/conflict-$1" output
  mkdir -p "${home}/.pi"
  case "${kind}" in
    directory) mkdir "${home}/.pi/agent" && printf 'keep\n' >"${home}/.pi/agent/marker" ;;
    foreign) ln -s /tmp/pi-elsewhere "${home}/.pi/agent" ;;
  esac
  if output="$(sudo env VERSION=1.4.0 _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${home}" bash "${INSTALLER}" 2>&1)"
  then
    printf '%s\n' "${output}"
    return 1
  fi
  [[ "${output}" == *"pi: error: ${home}/.pi/agent "* ]] || { printf '%s\n' "${output}"; return 1; }
  case "${kind}" in
    directory) [[ "$(cat "${home}/.pi/agent/marker")" == keep ]] ;;
    foreign) [[ "$(readlink "${home}/.pi/agent")" == /tmp/pi-elsewhere ]] ;;
  esac
}
for kind in directory foreign; do
  check "an existing ${kind} at ~/.pi/agent fails the build and is preserved" build_conflict_preserved "${kind}"
done

agent_dir_variable_rejected() {
  local output
  if output="$(sudo env VERSION=1.4.0 PI_CODING_AGENT_DIR="${work}/elsewhere" _REMOTE_USER="$(id -un)" \
    _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"; then
    printf '%s\n' "${output}"
    return 1
  fi
  [[ "${output}" == *"pi: error: PI_CODING_AGENT_DIR is set;"* && ! -e "${work}/elsewhere" ]] \
    || { printf '%s\n' "${output}"; return 1; }
}
check "a caller-provided PI_CODING_AGENT_DIR fails the build without changes" agent_dir_variable_rejected

# Replaces the feature's link with another tool's executable for one run and restores the link afterwards.
foreign_cli_preserved() {
  local output result=0
  sudo mv /usr/local/bin/pi "${work}/feature-link"
  printf '#!/bin/sh\necho other\n' | sudo tee /usr/local/bin/pi >/dev/null
  if output="$(sudo env VERSION=1.4.0 _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"
  then
    result=1
  fi
  [[ "${output}" == *"pi: error: /usr/local/bin/pi exists and is not this feature's link;"* ]] || result=1
  [[ "$(cat /usr/local/bin/pi)" == $'#!/bin/sh\necho other' ]] || result=1
  sudo mv --force "${work}/feature-link" /usr/local/bin/pi
  if [[ "${result}" != 0 ]]; then printf '%s\n' "${output}"; fi
  return "${result}"
}
check "another tool's /usr/local/bin/pi fails the build and is preserved" foreign_cli_preserved
check "the installed CLI is unchanged after every rejection" test "$(pi --version)" = "${before}"
check "the link still names the feature's installation" test "$(readlink /usr/local/bin/pi)" = /usr/local/lib/pi/pi
reportResults
