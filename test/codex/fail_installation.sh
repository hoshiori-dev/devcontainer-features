#!/usr/bin/env bash
# Run invalid inputs against the actual installer; stubs model an unsupported CPU and npm's integrity failure.
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
mkdir "${work}/cpu" "${work}/integrity"
printf '#!/bin/sh\nprintf "mips\\n"\n' >"${work}/cpu/uname"
cat >"${work}/integrity/npm" <<'STUB'
#!/bin/sh
if [ "$1" = view ]; then printf '"0.162.0"\n'; else printf 'npm error EINTEGRITY\n' >&2; exit 1; fi
STUB
chmod +x "${work}/cpu/uname" "${work}/integrity/npm"

rejects_environment() {
  local directory="$1" expected="$2" output
  if output="$(sudo env PATH="${directory}:${PATH}" VERSION=0.162.0 _REMOTE_USER="${REMOTE_USER}" \
    _REMOTE_USER_HOME="${REMOTE_HOME}" bash "${INSTALLER}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"codex: error: ${expected}"* ]]
}
check "unsupported CPU is rejected before installation" rejects_environment "${work}/cpu" "unsupported architecture"
check "npm integrity rejection fails installation" rejects_environment "${work}/integrity" "npm installation or integrity verification failed"
check "the installed CLI still runs after rejected replacements" codex --version
reportResults
