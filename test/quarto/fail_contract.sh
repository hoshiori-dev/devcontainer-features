#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
test_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${test_dir}/installer.sh"
FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR
mv /opt/quarto "${FIXTURE_DIR}/original"
cleanup() {
  rm -rf /opt/quarto /usr/local/bin/quarto
  mv "${FIXTURE_DIR}/original" /opt/quarto
  ln -s /opt/quarto/bin/quarto /usr/local/bin/quarto
  rm -rf "${FIXTURE_DIR}"
}
trap cleanup EXIT
rm /usr/local/bin/quarto
mkdir "${FIXTURE_DIR}/bin"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
chmod +x "${FIXTURE_DIR}/bin/curl"
printf 'normal\n' >"${FIXTURE_DIR}/mode"
printf '1.2.3\n' >"${FIXTURE_DIR}/latest"
make_release 1.2.3
make_release 1.2.4
check "verified fixture release installs" run_installer 1.2.3
requests_before="$(wc -l <"${FIXTURE_DIR}/requests")"
for value in '' 1.2 1.2.3-preview garbage; do
  if run_installer "${value}"; then exit 1; fi
  check "invalid version is rejected before requests: ${value}" grep -q 'invalid version' "${FIXTURE_DIR}/output"
done
check "invalid versions perform no downloads" test "$(wc -l <"${FIXTURE_DIR}/requests")" = "${requests_before}"
check "network failure preserves existing CLI" rejects_and_preserves network 'cannot resolve'
check "malformed metadata preserves existing CLI" rejects_and_preserves metadata 'invalid or prerelease'
check "numeric prerelease is rejected" rejects_and_preserves prerelease 'prerelease'
check "missing architecture archive is rejected" rejects_and_preserves missing_asset 'no.*archive'
check "missing checksum download preserves CLI" rejects_and_preserves missing_checksum 'required checksums'
check "missing checksum entry preserves CLI" rejects_and_preserves missing_entry 'missing, duplicated'
check "duplicated checksum entry preserves CLI" rejects_and_preserves duplicate 'missing, duplicated'
check "corrupt archive preserves CLI" rejects_and_preserves corrupt 'checksum mismatch'
printf 'normal\n' >"${FIXTURE_DIR}/mode"
make_release 1.2.4 incompatible
if run_installer 1.2.4; then exit 1; fi
check "incompatible runtime reports the selected release" grep -q 'release 1.2.4 cannot run' "${FIXTURE_DIR}/output"
check "incompatible runtime preserves previous CLI" test "$(quarto --version)" = 1.2.3
make_release 1.2.4 active_failure
if run_installer 1.2.4; then exit 1; fi
check "failed activation restores previous CLI" test "$(quarto --version)" = 1.2.3
make_release 1.2.4
check "upgrade selects the later version" run_installer v1.2.4
check "upgrade version is exact" test "$(quarto --version)" = 1.2.4
check "downgrade succeeds" run_installer 1.2.3
printf 'keep\n' >/opt/quarto/sentinel
check "healthy identical installation succeeds" run_installer 1.2.3
check "same-version skip retains tree" test -f /opt/quarto/sentinel
check "same-version skip is logged" grep -q 'skipping archive' "${FIXTURE_DIR}/output"
printf '1.2.4\n' >"${FIXTURE_DIR}/latest"
check "latest is resolved again" run_installer latest
check "latest activates current stable fixture" test "$(quarto --version)" = 1.2.4
printf '#!/bin/sh\nexit 1\n' >/opt/quarto/bin/quarto
chmod +x /opt/quarto/bin/quarto
printf 'corrupt\n' >"${FIXTURE_DIR}/mode"
if run_installer 1.2.4; then exit 1; fi
check "failed repair preserves the unhealthy tree" grep -q 'exit 1' /opt/quarto/bin/quarto
printf 'normal\n' >"${FIXTURE_DIR}/mode"
check "unhealthy exact version is repaired" run_installer 1.2.4
check "repair restores usable CLI" test "$(quarto --version)" = 1.2.4
mv /usr/local/bin/quarto "${FIXTURE_DIR}/link"
cat >/usr/local/bin/quarto <<'FOREIGN'
#!/bin/sh
# foreign installation with the same requested version
printf '1.2.3\n'
touch "${FIXTURE_DIR}/foreign_executed"
FOREIGN
chmod +x /usr/local/bin/quarto
if run_installer 1.2.3; then exit 1; fi
check "foreign command is preserved" grep -q foreign /usr/local/bin/quarto
check "foreign command is not executed even at the requested version" test ! -e "${FIXTURE_DIR}/foreign_executed"
rm /usr/local/bin/quarto
mv "${FIXTURE_DIR}/link" /usr/local/bin/quarto
mv /opt/quarto/.devcontainer-feature-quarto "${FIXTURE_DIR}/marker"
if run_installer 1.2.3; then exit 1; fi
check "unmanaged tree is rejected" grep -q unmanaged "${FIXTURE_DIR}/output"
mv "${FIXTURE_DIR}/marker" /opt/quarto/.devcontainer-feature-quarto
rm /usr/local/bin/quarto
ln -s /does/not/exist /usr/local/bin/quarto
if run_installer 1.2.3; then exit 1; fi
check "foreign broken symlink is preserved" test "$(readlink /usr/local/bin/quarto)" = /does/not/exist
rm /usr/local/bin/quarto
ln -s /opt/quarto/bin/quarto /usr/local/bin/quarto
printf '#!/bin/sh\necho foreign\n' >"${FIXTURE_DIR}/bin/quarto"
chmod +x "${FIXTURE_DIR}/bin/quarto"
if run_installer 1.2.3; then exit 1; fi
check "foreign command elsewhere on PATH is rejected" grep -q 'conflicts with this feature' "${FIXTURE_DIR}/output"
rm "${FIXTURE_DIR}/bin/quarto"
mkdir "${FIXTURE_DIR}/cwd"
printf '#!/bin/sh\necho foreign\n' >"${FIXTURE_DIR}/cwd/quarto"
chmod +x "${FIXTURE_DIR}/cwd/quarto"
pushd "${FIXTURE_DIR}/cwd" >/dev/null
if PATH="${PATH}:" run_installer 1.2.3; then exit 1; fi
check "an empty PATH entry detects a foreign command in the current directory" \
  grep -q 'conflicts with this feature' "${FIXTURE_DIR}/output"
popd >/dev/null
cp -L /etc/os-release "${FIXTURE_DIR}/os-release"
printf 'ID=unsupported\n' >/etc/os-release
if run_installer 1.2.3; then exit 1; fi
check "unsupported distribution is identified" grep -q 'unsupported distribution unsupported' "${FIXTURE_DIR}/output"
cat "${FIXTURE_DIR}/os-release" >/etc/os-release
printf '#!/bin/sh\necho ppc64le\n' >"${FIXTURE_DIR}/bin/uname"
chmod +x "${FIXTURE_DIR}/bin/uname"
if run_installer 1.2.3; then exit 1; fi
check "unsupported architecture is identified" grep -q 'unsupported architecture ppc64le' "${FIXTURE_DIR}/output"
rm "${FIXTURE_DIR}/bin/uname"
ln -s /does/not/exist /lib/ld-musl-quarto-test.so.1
if run_installer 1.2.3; then exit 1; fi
check "musl is rejected before requests" grep -q 'musl is unsupported' "${FIXTURE_DIR}/output"
rm /lib/ld-musl-quarto-test.so.1
reportResults
