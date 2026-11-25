#!/usr/bin/env bash
# Scenario "fail_install": the CLI installed incus on debian:13 with default options. The script runs the installer
# again with an invalid value of each option, with /etc/os-release naming an unsupported distribution, with a
# `dpkg` that names another architecture, and with a remote user that does not exist: each run must fail with its
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

# Another architecture: `dpkg --print-architecture` answered by a stand-in first on PATH, which hands every other
# call to the real dpkg.
mkdir "${work_dir}/dpkg"
cat >"${work_dir}/dpkg/dpkg" <<'STAND_IN'
#!/bin/sh
if [ "${1-}" = --print-architecture ]; then
  echo riscv64
else
  exec /usr/bin/dpkg "$@"
fi
STAND_IN
chmod +x "${work_dir}/dpkg/dpkg"
status=0
output="$(run_installer_with_stand_ins "${work_dir}/dpkg")" || status=$?
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

# Prints the binary OpenPGP data of the files given as one armored public key block, of the form the installer
# accepts: the begin line, an empty line, base64 lines with their checksum line, and the end line. gpg armors the
# data as a file of another kind, with a comment line; the block's name is changed and the comment dropped.
armor_key_block() {
  cat "$@" \
    | gpg --batch --homedir "${work_dir}/gnupg" --enarmor \
    | sed -e 's/PGP ARMORED FILE/PGP PUBLIC KEY BLOCK/' -e '/^Comment:/d'
}

# Runs the installer with the key file $1 as the answer to its download, sets ${output} and ${status}, and shows the
# end of the output.
install_with_key() {
  status=0
  output="$(run_installer_with_stand_ins "${work_dir}/curl" KEY_FIXTURE="$1")" || status=$?
  printf '%s\n' "${output}" | tail -n 4
}

# The last run failed with a message that matches the pattern $1, and changed no package and no configuration.
key_rejected_with() {
  ((status != 0)) || return
  grep -q -E "$1" <<<"${output}" || return
  [[ "$(packages)" == "${before}" && "$(configuration)" == "${configuration_before}" ]]
}

# The last run succeeded after it found the pinned fingerprint.
key_accepted() {
  ((status == 0)) && grep -q "the key has the pinned fingerprint ${PINNED}" <<<"${output}"
}

readonly PINNED="4EFC590696CB15B87C73A3AD82CC8797C838DCFD"
other_key="$(other_key_file)"
gpg --batch --homedir "${work_dir}/gnupg" --output "${work_dir}/pinned.gpg" --dearmor "${INCUS_KEY}"

# A key with another fingerprint, alone, in a well-formed block.
armor_key_block "${other_key}" >"${work_dir}/other.asc"
install_with_key "${work_dir}/other.asc"
check "Another key: a key with another fingerprint is not accepted, and the failure names the pinned one" \
  key_rejected_with "the key was not accepted: .* holds 1 primary key\\(s\\), .* exactly one, ${PINNED}"

# Another key beside the pinned one, inside one well-formed block.
armor_key_block "${work_dir}/pinned.gpg" "${other_key}" >"${work_dir}/two-keys.asc"
install_with_key "${work_dir}/two-keys.asc"
check "Another key: a second key in the same block is not accepted" \
  key_rejected_with 'the key was not accepted: .* holds 2 public key packet\(s\)'

# Another key beside the pinned one, in a second block.
cat "${INCUS_KEY}" "${work_dir}/other.asc" >"${work_dir}/two-blocks.asc"
install_with_key "${work_dir}/two-blocks.asc"
check "Another key: a second armored block is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'

# Another key in a block whose begin line gpg does not take for armor, so that gpg lists the pinned key alone,
# while a tool that starts a block at any line beginning with "-----BEGIN" would read both.
{
  echo '-----BEGIN'
  echo
  base64 "${other_key}"
  echo '-----END'
  cat "${INCUS_KEY}"
} >"${work_dir}/pseudo-block.asc"
install_with_key "${work_dir}/pseudo-block.asc"
check "Another key: a block that only some tools read is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'

# Another key after the pinned key's checksum line, inside the one block: gpg stops reading at the checksum line,
# while a tool that skips such lines would read on and find both keys.
{
  sed '$d' "${INCUS_KEY}"
  base64 "${other_key}"
  echo '-----END PGP PUBLIC KEY BLOCK-----'
} >"${work_dir}/after-checksum.asc"
install_with_key "${work_dir}/after-checksum.asc"
check "Another key: data after the checksum line of the block is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'

# Another key after a compressed data packet, behind the pinned key in one well-formed block: gpg's key listing
# ends at the compressed packet, while a tool that skips the packet by its length would read the second key. gpg
# itself makes the packet, from a line of text.
echo 'stand-in' | gpg --batch --homedir "${work_dir}/gnupg" --compress-algo zip --store \
  --output "${work_dir}/compressed.gpg"
armor_key_block "${work_dir}/pinned.gpg" "${work_dir}/compressed.gpg" "${other_key}" >"${work_dir}/compressed.asc"
install_with_key "${work_dir}/compressed.asc"
# gpg either names the compressed packet or, depending on its version, fails to list the packets at all; the
# installer refuses the file at that step in both cases.
check "Another key: a key behind a compressed data packet is not accepted" \
  key_rejected_with 'the key was not accepted: (gpg cannot list the OpenPGP packets|.* packets of the kind "compressed)'

# The pinned key with an armor header line, which the plain form the installer accepts does not have.
sed '1a Comment: stand-in' "${INCUS_KEY}" >"${work_dir}/header.asc"
install_with_key "${work_dir}/header.asc"
check "the pinned key with an armor header line is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'

# The pinned key with a line of text before its block, and with carriage returns at its line ends.
{
  echo 'Zabbly signing key'
  cat "${INCUS_KEY}"
} >"${work_dir}/text-before.asc"
install_with_key "${work_dir}/text-before.asc"
check "the pinned key with text before its block is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'
sed 's/$/\r/' "${INCUS_KEY}" >"${work_dir}/carriage-returns.asc"
install_with_key "${work_dir}/carriage-returns.asc"
check "the pinned key with carriage returns is not accepted" \
  key_rejected_with 'the key was not accepted: .* is not exactly one armored public key block'

# The pinned key as the installer accepts it: the run gets past the key and installs nothing new.
install_with_key "${INCUS_KEY}"
check "Pinned key: the installed key file, served again, is accepted" key_accepted

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

# A secret key beside the pinned key, in one well-formed block: gpg lists it apart from the public keys, and only
# where a gpg-agent can start, which is installed for this case alone. The key is made here.
as_root apt-get update >/dev/null
as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends gpg-agent >/dev/null
before="$(packages)"
gpg --batch --quiet --homedir "${work_dir}/gnupg" --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Stand-in key' ed25519 sign never
gpg --batch --quiet --homedir "${work_dir}/gnupg" --pinentry-mode loopback --passphrase '' \
  --output "${work_dir}/secret.gpg" --export-secret-keys
armor_key_block "${work_dir}/pinned.gpg" "${work_dir}/secret.gpg" >"${work_dir}/secret-key.asc"
install_with_key "${work_dir}/secret-key.asc"
check "Another key: a secret key beside the pinned key is not accepted" \
  key_rejected_with 'the key was not accepted: .* packets of the kind "secret key packet'
check "the installed feature still works: the start check exits zero" "${INCUS_CHECK}"

gpgconf --homedir "${work_dir}/gnupg" --kill gpg-agent || true
rm -rf "${work_dir:?}"
reportResults
