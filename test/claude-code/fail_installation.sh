#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
before="$(claude --version)"
rejects() {
  local version="$1"
  if sudo env VERSION="${version}" _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" \
    bash "${INSTALLER}"; then return 1; fi
}
for version in '' bad v2.1.89 2.1.89-beta.1 0.0.1 9999.0.0; do
  check "invalid or old release is rejected: ${version}" rejects "${version}"
done
check "the existing CLI survives rejected installations" claude --version
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir "${work}/signature" "${work}/checksum" "${work}/platform"
cat >"${work}/platform/uname" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  --kernel-name) printf '%s\n' "${FIXTURE_KERNEL}" ;;
  --machine) printf '%s\n' "${FIXTURE_MACHINE}" ;;
  *) exec /usr/bin/uname "$@" ;;
esac
STUB
chmod +x "${work}/platform/uname"
rejects_platform() {
  local kernel="$1" machine="$2" expected="$3" output
  if output="$(sudo env PATH="${work}/platform:${PATH}" FIXTURE_KERNEL="${kernel}" FIXTURE_MACHINE="${machine}" \
    VERSION=latest _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"${expected}"* ]]
}
check "uncovered systems fail with the actual cause" rejects_platform Darwin x86_64 "unsupported system"
check "uncovered architectures fail with the actual cause" rejects_platform Linux riscv64 "unsupported architecture riscv64"
cat >"${work}/signature/gpg" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do if [[ "${arg}" == --verify ]]; then exit 1; fi; done
exec /usr/bin/gpg "$@"
STUB
cat >"${work}/checksum/curl" <<'STUB'
#!/usr/bin/env bash
url="${!#}"
if [[ "${url}" == */linux-*/claude ]]; then
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == --output ]]; then printf 'corrupt binary\n' >"$2"; exit 0; fi
    shift
  done
  exit 1
fi
exec /usr/bin/curl "$@"
STUB
chmod +x "${work}/signature/gpg" "${work}/checksum/curl"
rejects_verification() {
  local kind="$1" expected="$2" output
  if output="$(sudo env PATH="${work}/${kind}:${PATH}" VERSION=2.1.89 _REMOTE_USER="$(id -un)" \
    _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"; then return 1; fi
  [[ "${output}" == *"${expected}"* ]]
}
check "a failed manifest signature blocks replacement" rejects_verification signature "manifest signature verification failed"
check "a corrupt native binary blocks replacement" rejects_verification checksum "binary checksum verification failed"
check "verification failures preserve the working CLI version" test "$(claude --version)" = "${before}"
reportResults
