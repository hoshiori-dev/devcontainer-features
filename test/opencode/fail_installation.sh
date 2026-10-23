#!/usr/bin/env bash
# Runs the installer against invalid options, uncovered platforms, and registry fixtures served by a curl stub, and
# checks that every rejection leaves the installed CLI in place.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
before="$(opencode --version)"
readonly before
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

# Runs the installer as root with VERSION=$1 and extra PATH directory $2, and succeeds when it fails with an error
# message containing $3.
rejects() {
  local version="$1" directory="$2" expected="$3" output
  if output="$(sudo env PATH="${directory:+${directory}:}${PATH}" VERSION="${version}" \
    OPENCODE_TEST_CASE="${case_name-}" OPENCODE_TEST_DIR="${work}" _REMOTE_USER="$(id -un)" \
    _REMOTE_USER_HOME="${HOME}" bash "${INSTALLER}" 2>&1)"; then
    printf '%s\n' "${output}"
    return 1
  fi
  [[ "${output}" == *"opencode: error: ${expected}"* ]] || { printf '%s\n' "${output}"; return 1; }
}

# This literal shell syntax must reach option validation without expansion.
# shellcheck disable=SC2016
for version in "" v2.1.3 2.1.3-beta.1 2.1 '$(touch /tmp/opencode-option-executed)'; do
  check "a malformed or prerelease version is rejected: ${version}" rejects "${version}" "" "option version is"
done
check "version input is never evaluated as shell code" test ! -e /tmp/opencode-option-executed
for version in 1.19.4 3.0.0; do
  check "a release outside stable 2.x is rejected: ${version}" rejects "${version}" "" "supports stable OpenCode 2.x"
done
check "an unpublished 2.x release is rejected" rejects 2.999.0 "" "release 2.999.0 is unavailable"

mkdir "${work}/system" "${work}/cpu"
printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"${work}/system/uname"
cat >"${work}/cpu/uname" <<'STUB'
#!/bin/sh
case "$1" in --kernel-name) printf 'Linux\n' ;; *) printf 'mips\n' ;; esac
STUB
chmod +x "${work}/system/uname" "${work}/cpu/uname"
check "an uncovered system is rejected" rejects 2.1.2 "${work}/system" "unsupported system"
check "an uncovered CPU is rejected" rejects 2.1.2 "${work}/cpu" "unsupported architecture"

# A registry stub: OPENCODE_TEST_CASE selects the fixture and every requested URL is appended to requests.log.
mkdir -p "${work}/registry" "${work}/package/package/bin"
printf '#!/bin/sh\nexit 37\n' >"${work}/package/package/bin/opencode"
chmod +x "${work}/package/package/bin/opencode"
tar -czf "${work}/broken.tgz" -C "${work}/package" package
cat >"${work}/registry/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
output=""
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == --output ]]; then output="$2"; shift; fi
  shift
done
printf '%s\n' "${url}" >>"${OPENCODE_TEST_DIR}/requests.log"
integrity="sha512-$(sha512sum "${OPENCODE_TEST_DIR}/broken.tgz" | cut -d ' ' -f 1 | tr a-f A-F | basenc --base16 -d \
  | base64 -w 0)"
target="${url#*/@opencode%2fcli-}"
target="${target%%/*}"
tarball="https://registry.npmjs.org/@opencode/cli-${target}/-/cli-${target}-2.1.2.tgz"
case "${OPENCODE_TEST_CASE}:${url}" in
  latest_prerelease:*/dist-tags) printf '{"latest":"2.2.0-beta.1"}\n' ;;
  foreign_tarball:*/2.1.2)
    jq -n --arg integrity "${integrity}" '{dist:{tarball:"https://example.invalid/opencode.tgz",integrity:$integrity}}' ;;
  no_integrity:*/2.1.2) jq -n --arg tarball "${tarball}" '{dist:{tarball:$tarball}}' ;;
  corrupt:*/2.1.2 | broken:*/2.1.2)
    jq -n --arg tarball "${tarball}" --arg integrity "${integrity}" '{dist:{tarball:$tarball,integrity:$integrity}}' ;;
  corrupt:*.tgz) printf 'corrupt package\n' >"${output}" ;;
  broken:*.tgz) cp "${OPENCODE_TEST_DIR}/broken.tgz" "${output}" ;;
  *) exit 22 ;;
esac
STUB
chmod +x "${work}/registry/curl"

case_name=latest_prerelease
check "a latest dist-tag outside stable 2.x is rejected" rejects latest "${work}/registry" "not a stable 2.x release"
check "no package is requested after a rejected dist-tag" bash -c "! grep -q 'cli-linux' '${work}/requests.log'"
case_name=foreign_tarball
check "a tarball outside the registry package is rejected" rejects 2.1.2 "${work}/registry" "unexpected tarball"
case_name=no_integrity
check "a package without SHA-512 integrity is rejected" rejects 2.1.2 "${work}/registry" "no SHA-512 integrity"
case_name=corrupt
check "a package that does not match its integrity is rejected" rejects 2.1.2 "${work}/registry" \
  "does not match its published integrity"
case_name=broken
check "a verified executable that cannot run is rejected" rejects 2.1.2 "${work}/registry" "cannot run"

# The expected package depends on the test machine: upstream's installer selects -baseline without AVX2.
expected_target=linux-arm64
if [[ "$(uname -m)" == x86_64 ]]; then
  expected_target=linux-x64
  if ! grep -qwi avx2 /proc/cpuinfo; then expected_target=linux-x64-baseline; fi
fi
check "the platform package follows upstream's target selection" \
  grep -qx "https://registry.npmjs.org/@opencode%2fcli-${expected_target}/2.1.2" "${work}/requests.log"
check "the installed CLI is unchanged after every rejection" test "$(opencode --version)" = "${before}"
reportResults
