#!/usr/bin/env bash
# Invalid inputs and local download fixtures exercise the actual installer's native support and verification boundary.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
REMOTE_USER="$(id -un)"
readonly REMOTE_USER
readonly REMOTE_HOME="${HOME}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

rejects_version() {
  local version="$1" output
  if output="$(sudo env PATH="${PATH}" VERSION="${version}" _REMOTE_USER="${REMOTE_USER}" _REMOTE_USER_HOME="${REMOTE_HOME}" \
    bash "${INSTALLER}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"codex: error:"* ]]
}

# This literal shell syntax must reach option validation without expansion.
# shellcheck disable=SC2016
for version in "" v0.163.0 0.163.0-beta.1 '$(touch /tmp/codex-option-executed)' 999999.0.0; do
  check "invalid or unavailable release is rejected: ${version}" rejects_version "${version}"
done
check "version input is never evaluated as shell code" test ! -e /tmp/codex-option-executed
mkdir "${work}/cpu" "${work}/system" "${work}/downloads"
mkdir -p "${work}/runtime/bin" "${work}/runtime/codex-path"
printf '#!/bin/sh\nexit 37\n' >"${work}/runtime/bin/codex"
printf '#!/bin/sh\nexit 0\n' >"${work}/runtime/bin/codex-code-mode-host"
cp "${work}/runtime/bin/codex-code-mode-host" "${work}/runtime/codex-path/rg"
chmod +x "${work}/runtime/bin/"* "${work}/runtime/codex-path/rg"
tar -czf "${work}/runtime.tar.gz" -C "${work}/runtime" .
cat >"${work}/cpu/uname" <<'STUB'
#!/bin/sh
case "$1" in --kernel-name) printf 'Linux\n' ;; *) printf 'mips\n' ;; esac
STUB
printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"${work}/system/uname"
cat >"${work}/downloads/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
output=""
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
case "$(uname --machine)" in
  x86_64) target=x86_64 ;; aarch64) target=aarch64 ;;
esac
asset="codex-package-${target}-unknown-linux-musl.tar.gz"
case "${url}" in
  */tags/rust-v0.162.0)
    if [[ "${CODEX_TEST_DOWNLOAD_CASE}" == no_asset ]]; then
      printf '{"tag_name":"rust-v0.162.0","draft":false,"prerelease":false,"assets":[]}' >"${output}"
    else
      jq -n --arg asset "${asset}" \
        '{tag_name:"rust-v0.162.0",draft:false,prerelease:false,assets:[{name:$asset}]}' >"${output}"
    fi
    ;;
  */codex-package_SHA256SUMS)
    if [[ "${CODEX_TEST_DOWNLOAD_CASE}" == no_manifest ]]; then exit 22; fi
    if [[ "${CODEX_TEST_DOWNLOAD_CASE}" == runtime_failure ]]; then
      printf '%s  %s\n' "$(sha256sum "${CODEX_TEST_ARCHIVE}" | cut -d ' ' -f 1)" "${asset}" >"${output}"
    else
      printf '%064d  %s\n' 0 "${asset}" >"${output}"
    fi
    ;;
  *.tar.gz)
    if [[ "${CODEX_TEST_DOWNLOAD_CASE}" == runtime_failure ]]; then
      cp "${CODEX_TEST_ARCHIVE}" "${output}"
    else
      printf 'corrupt native archive\n' >"${output}"
    fi
    ;;
  *) exit 23 ;;
esac
STUB
chmod +x "${work}/cpu/uname" "${work}/system/uname" "${work}/downloads/curl"

rejects_environment() {
  local directory="$1" expected="$2" mode="${3-integrity}" output
  if output="$(sudo env PATH="${directory}:${PATH}" CODEX_TEST_DOWNLOAD_CASE="${mode}" \
    CODEX_TEST_ARCHIVE="${work}/runtime.tar.gz" VERSION=0.162.0 _REMOTE_USER="${REMOTE_USER}" _REMOTE_USER_HOME="${REMOTE_HOME}" bash "${INSTALLER}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"codex: error: ${expected}"* ]]
}
check "uncovered system is rejected before installation" rejects_environment "${work}/system" "unsupported system"
check "uncovered CPU is rejected before installation" rejects_environment "${work}/cpu" "unsupported architecture"
check "missing release package is unsupported without a fallback" rejects_environment \
  "${work}/downloads" "unsupported target for release" no_asset
check "missing checksum manifest fails installation" rejects_environment \
  "${work}/downloads" "cannot download required release checksum manifest" no_manifest
check "native checksum rejection fails installation" rejects_environment \
  "${work}/downloads" "native package checksum verification failed"
check "a verified native payload that cannot execute fails before replacement" rejects_environment \
  "${work}/downloads" "native package cannot execute or reports an unexpected version" runtime_failure
check "the installed CLI still runs after rejected replacements" codex --version
reportResults
