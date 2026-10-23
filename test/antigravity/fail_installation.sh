#!/usr/bin/env bash
# Local manifest and archive fixtures exercise the installer's verification and platform boundary; each rejected run
# must leave the working CLI in place.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# The scenario runner copies this helper beside the script; hooks may lint each script independently.
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"
readonly ARCHIVE_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/9.9.9-1/linux-x64/cli.tar.gz"
fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT
make_curl_stub "${fixtures}/downloads"

before="$(agy --version)"
cp /usr/local/share/antigravity/agy "${fixtures}/working-agy"
make_archive "${fixtures}/good.tar.gz" 'echo 9.9.9'
make_archive "${fixtures}/broken.tar.gz" 'exit 37'
tar -czf "${fixtures}/empty.tar.gz" -C "${fixtures}/downloads" curl

rejects_manifest() {
  local expected="$1" version="$2" url="$3" digest="$4" archive="$5"
  make_manifest "${fixtures}/manifest.json" "${version}" "${url}" "${digest}"
  run_install "${fixtures}/downloads" "${fixtures}/manifest.json" "${archive}"
  failed_with "${expected}"
}
outside="the manifest's archive URL is outside the allowed distribution prefix"
check "an archive URL on another host is rejected" rejects_manifest "${outside}" \
  9.9.9 https://example.com/antigravity-cli/cli.tar.gz "${fixtures}/good.tar.gz" "${fixtures}/good.tar.gz"
check "an archive URL without HTTPS is rejected" rejects_manifest "${outside}" \
  9.9.9 "http${ARCHIVE_URL#https}" "${fixtures}/good.tar.gz" "${fixtures}/good.tar.gz"
check "an archive URL leaving the distribution prefix is rejected" rejects_manifest "${outside}" \
  9.9.9 "https://storage.googleapis.com/antigravity-public/antigravity-cli/../other/cli.tar.gz" \
  "${fixtures}/good.tar.gz" "${fixtures}/good.tar.gz"
check "a manifest without a SHA-512 digest is rejected" rejects_manifest \
  "the platform manifest has no valid SHA-512 digest" 9.9.9 "${ARCHIVE_URL}" "" "${fixtures}/good.tar.gz"
check "a manifest without a valid version is rejected" rejects_manifest \
  "the platform manifest names no valid version" latest "${ARCHIVE_URL}" "${fixtures}/good.tar.gz" \
  "${fixtures}/good.tar.gz"
check "an archive that does not match the digest is rejected" rejects_manifest \
  "the archive does not match the manifest's SHA-512 digest" 9.9.9 "${ARCHIVE_URL}" "${fixtures}/broken.tar.gz" \
  "${fixtures}/good.tar.gz"
check "a verified archive without the executable is rejected" rejects_manifest \
  "the verified archive holds no antigravity executable" 9.9.9 "${ARCHIVE_URL}" "${fixtures}/empty.tar.gz" \
  "${fixtures}/empty.tar.gz"
check "a verified executable that cannot run is rejected before replacement" rejects_manifest \
  "the verified executable cannot run or reports a version other than 9.9.9" 9.9.9 "${ARCHIVE_URL}" \
  "${fixtures}/broken.tar.gz" "${fixtures}/broken.tar.gz"

unreachable_manifest() {
  run_install "${fixtures}/downloads" "" "${fixtures}/good.tar.gz"
  failed_with "cannot download the"
}
check "an unreachable manifest fails installation" unreachable_manifest

mkdir "${fixtures}/system" "${fixtures}/cpu"
printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"${fixtures}/system/uname"
cat >"${fixtures}/cpu/uname" <<'STUB'
#!/bin/sh
case "$1" in --kernel-name) printf 'Linux\n' ;; *) printf 'mips\n' ;; esac
STUB
chmod +x "${fixtures}/system/uname" "${fixtures}/cpu/uname"
rejects_platform() {
  run_install "$1:${fixtures}/downloads" "${fixtures}/manifest.json" "${fixtures}/good.tar.gz"
  failed_with "$2"
}
check "an uncovered system fails with the cause" rejects_platform "${fixtures}/system" "unsupported system"
check "an uncovered CPU fails with the cause" rejects_platform "${fixtures}/cpu" "unsupported architecture mips"

check "rejected installations leave the working executable unchanged" \
  cmp /usr/local/share/antigravity/agy "${fixtures}/working-agy"
check "the working CLI still reports its version" test "$(agy --version)" = "${before}"
check "rejected installations leave no staged executable" test ! -e /usr/local/share/antigravity/.agy.new
reportResults
