#!/usr/bin/env bash
# Scenario "fail_install": the CLI installed incus on debian:13 with default options. The script runs the installer
# again with an invalid value of each option, with /etc/os-release naming an unsupported distribution, with a
# `uname` that names another architecture, and with a remote user that does not exist: each run must fail with its
# reason before anything changes ("Unsupported distribution", "Unsupported architecture", "Unknown channel"). With a
# `curl` stand-in that serves the key file, it then checks the key rules ("Another key", "Key unavailable"), and
# with a codename the repository does not serve, the failing build ("Release the repository does not serve").
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

packages() {
  dpkg-query -W -f='${Package} ${Version}\n' | sha256sum
}

# One digest over the repository definition, the key, and the start settings.
configuration() {
  cat "${INCUS_SOURCES}" "${INCUS_KEY}" "${INCUS_SETTINGS}" | sha256sum
}

# Runs the installer with the directory $1 first on PATH and the remaining NAME=value pairs in its environment.
run_installer_with_stand_ins() {
  local stand_ins="$1"
  shift
  as_root env -i PATH="${stand_ins}:${SYSTEM_PATH}" HOME=/root "$@" bash "$(dirname "$0")/_feature/install.sh" 2>&1
}

# Prints the first key file under /usr/share/keyrings that holds exactly one primary key: a key other than Zabbly's.
other_key_file() {
  local file count
  for file in /usr/share/keyrings/*.gpg; do
    count="$(gpg --batch --homedir "${work_dir}/gnupg" --show-keys --with-colons "${file}" | grep -c '^pub:')"
    if [[ "${count}" == 1 ]]; then
      printf '%s\n' "${file}"
      return 0
    fi
  done
  return 1
}

before="$(packages)"
configuration_before="$(configuration)"
work_dir="$(mktemp -d)"
chmod a+rx "${work_dir}"
mkdir -m 700 "${work_dir}/gnupg"

status=0
output="$(run_installer CHANNEL=daily)" || status=$?
printf '%s\n' "${output}"
check "Unknown channel: the install fails" test "${status}" -ne 0
check "Unknown channel: the failure names the accepted values" \
  grep -q 'option channel is "daily"; use stable, lts-7.0, or lts-6.0' <<<"${output}"

status=0
output="$(run_installer VM=yes)" || status=$?
printf '%s\n' "${output}"
check "an invalid vm fails the install" test "${status}" -ne 0
check "the failure names the accepted values of vm" grep -q 'option vm is "yes"; use true or false' <<<"${output}"

status=0
output="$(run_installer INITIALIZE=auto)" || status=$?
printf '%s\n' "${output}"
check "an invalid initialize fails the install" test "${status}" -ne 0
check "the failure names the accepted values of initialize" \
  grep -q 'option initialize is "auto"; use minimal or none' <<<"${output}"

cp /etc/os-release "${work_dir}/os-release"
printf '%s\n' 'ID=alpine' 'VERSION_ID=3.22' | as_root tee /etc/os-release >/dev/null
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}"
as_root cp "${work_dir}/os-release" /etc/os-release
check "Unsupported distribution: the install fails" test "${status}" -ne 0
check "Unsupported distribution: the failure names the detected distribution" \
  grep -q 'unsupported distribution "alpine"' <<<"${output}"

# Another architecture: `uname --machine` answered by a stand-in first on PATH.
mkdir "${work_dir}/uname"
printf '#!/bin/sh\necho riscv64\n' >"${work_dir}/uname/uname"
chmod +x "${work_dir}/uname/uname"
status=0
output="$(run_installer_with_stand_ins "${work_dir}/uname")" || status=$?
printf '%s\n' "${output}"
check "Unsupported architecture: the install fails" test "${status}" -ne 0
check "Unsupported architecture: the failure names the detected architecture" \
  grep -q 'unsupported architecture "riscv64"' <<<"${output}"

status=0
output="$(run_installer _REMOTE_USER=nobody-of-this-name)" || status=$?
printf '%s\n' "${output}"
check "a remote user that does not exist fails the install" test "${status}" -ne 0
check "the failure names the user" \
  grep -q 'the remote user "nobody-of-this-name" does not exist in the image' <<<"${output}"

# The key rules: a `curl` stand-in writes the file ${KEY_FIXTURE} to the path after --output, or fails like a 404
# when the fixture does not exist. The installer asks curl for nothing but the key.
mkdir "${work_dir}/curl"
cat >"${work_dir}/curl/curl" <<'STAND_IN'
#!/bin/sh
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ ! -f "${KEY_FIXTURE}" ]; then
  echo 'curl: (22) The requested URL returned error: 404' >&2
  exit 22
fi
cp "${KEY_FIXTURE}" "${output}"
STAND_IN
chmod +x "${work_dir}/curl/curl"

# Another key alone: a Debian archive key, armored as a public key block.
other_key="$(other_key_file)"
gpg --batch --homedir "${work_dir}/gnupg" --enarmor <"${other_key}" \
  | sed 's/PGP ARMORED FILE/PGP PUBLIC KEY BLOCK/' >"${work_dir}/other.asc"
status=0
output="$(run_installer_with_stand_ins "${work_dir}/curl" KEY_FIXTURE="${work_dir}/other.asc")" || status=$?
printf '%s\n' "${output}"
check "Another key: a key with another fingerprint fails the install" test "${status}" -ne 0
check "Another key: the failure says the key was not accepted and names the pinned fingerprint" \
  grep -q 'the key was not accepted: .*4EFC590696CB15B87C73A3AD82CC8797C838DCFD' <<<"${output}"

# Another key beside the pinned one, in a second armored block.
cat "${INCUS_KEY}" "${work_dir}/other.asc" >"${work_dir}/both.asc"
status=0
output="$(run_installer_with_stand_ins "${work_dir}/curl" KEY_FIXTURE="${work_dir}/both.asc")" || status=$?
printf '%s\n' "${output}"
check "Another key: a key beside the pinned one fails the install" test "${status}" -ne 0
check "Another key: the failure says the key was not accepted" grep -q 'the key was not accepted' <<<"${output}"

# A second block that is not a public key block, which gpg does not list.
gpg --batch --homedir "${work_dir}/gnupg" --enarmor <"${other_key}" >"${work_dir}/file-block.asc"
cat "${INCUS_KEY}" "${work_dir}/file-block.asc" >"${work_dir}/hidden.asc"
status=0
output="$(run_installer_with_stand_ins "${work_dir}/curl" KEY_FIXTURE="${work_dir}/hidden.asc")" || status=$?
printf '%s\n' "${output}"
check "Another key: a second armored block of another kind fails the install" test "${status}" -ne 0
check "Another key: the failure counts the armored blocks" \
  grep -q 'the key was not accepted: .* holds 2 armored block(s), 1 of them a public key block' <<<"${output}"

status=0
output="$(run_installer_with_stand_ins "${work_dir}/curl" KEY_FIXTURE="${work_dir}/missing.asc")" || status=$?
printf '%s\n' "${output}"
check "Key unavailable: the install fails" test "${status}" -ne 0
check "Key unavailable: the failure names the URL" \
  grep -q 'cannot download https://pkgs.zabbly.com/key.asc' <<<"${output}"

check "the installed packages are unchanged by the failed runs" test "${before}" = "$(packages)"
check "the repository definition, the key, and the start settings are unchanged by the failed runs" \
  test "${configuration_before}" = "$(configuration)"

# A release the repository does not serve: the build fails at the repository's index. The run rewrites the
# repository definition before it fails, so the definition is put back afterwards.
cp "${INCUS_SOURCES}" "${work_dir}/sources"
sed 's/^VERSION_CODENAME=.*/VERSION_CODENAME=forky/' "${work_dir}/os-release" | as_root tee /etc/os-release >/dev/null
status=0
output="$(run_installer)" || status=$?
printf '%s\n' "${output}" | tail -n 15
as_root cp "${work_dir}/os-release" /etc/os-release
as_root cp "${work_dir}/sources" "${INCUS_SOURCES}"
check "Release the repository does not serve: the install fails" test "${status}" -ne 0
check "Release the repository does not serve: the failure names the suite" \
  grep -q 'apt-get update failed with the Zabbly repository defined; the repository serves the suite "forky"' \
  <<<"${output}"
check "the installed packages are unchanged by the failed run" test "${before}" = "$(packages)"
check "the installed feature still works: the start check exits zero" "${INCUS_CHECK}"

rm -rf "${work_dir}"
reportResults
