#!/bin/sh
# Scenario fail_contract: debian:12 with the default option. Runs install.sh itself against local fixtures served by a
# curl stand-in, to check option and platform rejection, the target check, the handling of the Checkpoint answer,
# transport failures and redirects, signature and checksum verification, the same release without a download, and the
# replacement of an unreadable binary. Every rejected run must leave the installed packer, the packages, and the
# temporary directory as they were. The build's binary is restored at the end. POSIX sh, like the other packer tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

test_dir="$(cd "$(dirname "$0")" && pwd)"
installer="${test_dir}/_feature/install.sh"
readonly TARGET="/usr/local/bin/packer"
readonly RELEASES="releases.hashicorp.com/packer"
readonly CHECKPOINT="checkpoint-api.hashicorp.com/v1/check/packer"
readonly KEY="www.hashicorp.com/.well-known/pgp-key.txt"
readonly FINGERPRINT="C874011F0AB405110D02105534365D9472D7468F"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
esac
archive_name="packer_1.7.0_linux_${arch}.zip"
# Saved before it is cut to the first line, so a failing packer stops the script here instead of hiding in a pipeline.
installed_version="$(isolated_packer version)"
installed_version="$(printf '%s\n' "${installed_version}" | sed -n 1p)"
installed_version="${installed_version#Packer v}"

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR
fixtures="${FIXTURE_DIR}/fixtures"
mkdir -p "${fixtures}" "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/uname" "${FIXTURE_DIR}/original"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
# shellcheck disable=SC2016 # The stand-in's own parameters, expanded when it runs.
printf '#!/bin/sh\nif [ "${1-}" = --machine ]; then echo riscv64; else exec /usr/bin/uname "$@"; fi\n' \
  >"${FIXTURE_DIR}/uname/uname"
chmod +x "${FIXTURE_DIR}/bin/curl" "${FIXTURE_DIR}/uname/uname"
touch "${FIXTURE_DIR}/requests" "${FIXTURE_DIR}/violations"

# The build's binary, restored at the end whatever the cases did to it.
cp -p "${TARGET}" "${FIXTURE_DIR}/original/packer"
restore() {
  if [ -e /usr/bin/apt-get.hidden ]; then mv /usr/bin/apt-get.hidden /usr/bin/apt-get; fi
  if [ -e /etc/os-release.saved ] || [ -L /etc/os-release.saved ]; then
    rm -f /etc/os-release
    mv /etc/os-release.saved /etc/os-release
  fi
  rm -rf "${TARGET}"
  cp -p "${FIXTURE_DIR}/original/packer" "${TARGET}"
  rm -rf "${FIXTURE_DIR}"
}
trap restore EXIT

# Replaces ${TARGET} with file $1 by a rename next to it, never by writing into it: writing into an executable that has
# just run can fail with "Text file busy".
replace_target() {
  cp -p "$1" /usr/local/bin/.fixture-replacement
  mv -f /usr/local/bin/.fixture-replacement "${TARGET}"
}

# Preparation, before the baselines: the real key, the signed lists of 1.7.0 and 1.7.1 (which names no archive of
# 1.7.0), and the real 1.7.0 archive, fetched with the real curl; and gpg-agent, which only this script needs, to make
# a key that is not upstream's.
real_fetch() {
  /usr/bin/curl --proto '=https' --fail --silent --show-error --retry 3 --output "$1" "$2"
}
real_fetch "${fixtures}/hashicorp.asc" "https://${KEY}"
for release in 1.7.0 1.7.1; do
  real_fetch "${fixtures}/sums-${release}" "https://${RELEASES}/${release}/packer_${release}_SHA256SUMS"
  real_fetch "${fixtures}/sums-${release}.sig" "https://${RELEASES}/${release}/packer_${release}_SHA256SUMS.sig"
done
real_fetch "${fixtures}/${archive_name}" "https://${RELEASES}/1.7.0/${archive_name}"
printf 'not a Packer archive\n' >"${fixtures}/fake.zip"
DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends gpg-agent >/dev/null
rm -rf /var/lib/apt/lists/*

other_home="${FIXTURE_DIR}/other-gnupg"
mkdir -m 700 "${other_home}"
other_gpg() {
  gpg --batch --quiet --homedir "${other_home}" --pinentry-mode loopback --passphrase '' "$@"
}
other_gpg --quick-gen-key 'Fixture signer <fixture@example.invalid>' ed25519 sign never
# One armored block holding both keys: gpg --dearmor reads only the first block of a file.
other_gpg --import "${fixtures}/hashicorp.asc"
other_gpg --armor --export >"${fixtures}/key-with-other.asc"
other_gpg --output "${fixtures}/sums-1.7.0.other-sig" --detach-sign "${fixtures}/sums-1.7.0"
gpgconf --homedir "${other_home}" --kill gpg-agent

# A list derived from the real one: one byte of a checksum changed after signing.
sed '5s/^./0/' "${fixtures}/sums-1.7.0" >"${fixtures}/altered-1.7.0"
if cmp -s "${fixtures}/sums-1.7.0" "${fixtures}/altered-1.7.0"; then
  sed '5s/^./1/' "${fixtures}/sums-1.7.0" >"${fixtures}/altered-1.7.0"
fi

# Serves nothing; each case then serves what it needs.
reset_serve() {
  rm -rf "${FIXTURE_DIR}/serve"
  mkdir -p "${FIXTURE_DIR}/serve/${RELEASES}/1.7.0" "${FIXTURE_DIR}/serve/${KEY%/*}" \
    "${FIXTURE_DIR}/serve/${CHECKPOINT%/*}"
}
serve() {
  cp "$1" "${FIXTURE_DIR}/serve/$2"
}
# Serves the key $1, the list $2 with signature $3, and archive $4 as release 1.7.0; an empty argument serves nothing
# in its place.
serve_release() {
  reset_serve
  if [ -n "$1" ]; then serve "$1" "${KEY}"; fi
  if [ -n "$2" ]; then serve "$2" "${RELEASES}/1.7.0/packer_1.7.0_SHA256SUMS"; fi
  if [ -n "$3" ]; then serve "$3" "${RELEASES}/1.7.0/packer_1.7.0_SHA256SUMS.sig"; fi
  if [ -n "$4" ]; then serve "$4" "${RELEASES}/1.7.0/${archive_name}"; fi
}
# Serves the real release 1.7.0 whole.
serve_real_release() {
  serve_release "${fixtures}/hashicorp.asc" "${fixtures}/sums-1.7.0" "${fixtures}/sums-1.7.0.sig" \
    "${fixtures}/${archive_name}"
}
# Makes the Checkpoint service answer with the text $1, without clearing what is served.
serve_checkpoint() {
  printf '%s\n' "$1" >"${FIXTURE_DIR}/serve/${CHECKPOINT}"
}
# Makes the URL path $1 answer with a redirect that is not followed.
serve_redirect() {
  printf 302 >"${FIXTURE_DIR}/serve/$1.status"
}

target_state() {
  if [ -f "${TARGET}" ]; then
    printf '%s %s\n' "$(sha256sum <"${TARGET}")" "$(stat -c '%i %Y' "${TARGET}")"
  else
    printf 'not a regular file: %s\n' "${TARGET}"
  fi
}
packages_state() {
  dpkg-query --show --showformat '${Package} ${Version}\n'
}
baseline_target="$(target_state)"
baseline_packages="$(packages_state)"

# Runs install.sh with the curl stand-in first on PATH and the given environment assignments; sets ${run_status} and
# ${run_output}.
run_installer() {
  : >"${FIXTURE_DIR}/requests"
  run_status=0
  run_output="$(env PATH="${FIXTURE_DIR}/bin:${PATH}" "$@" sh "${installer}" 2>&1)" || run_status=$?
}

# Shows the run's output and the requests it made, for a failed check.
show_run() {
  printf '%s\n' "${run_output}" | sed 's/^/  | /'
  sed 's/^/  request: /' "${FIXTURE_DIR}/requests"
}

# Checks the last run: it failed with output holding $1; it made no request when $2 is "none", any requests when $2 is
# "any", or no request whose URL holds $2 otherwise; and every request carried the required flags.
last_run_failed() {
  if [ "${run_status}" -eq 0 ]; then
    echo '  the install succeeded'
    return 1
  fi
  case "${run_output}" in
    *"$1"*) ;;
    *)
      printf '  the output does not hold: %s\n' "$1"
      return 1
      ;;
  esac
  if [ "$2" = "none" ]; then
    if [ -s "${FIXTURE_DIR}/requests" ]; then
      echo '  requests were made'
      return 1
    fi
  elif [ "$2" != "any" ] && grep -q -F "$2" "${FIXTURE_DIR}/requests"; then
    printf '  a request holds %s\n' "$2"
    return 1
  fi
  if [ -s "${FIXTURE_DIR}/violations" ]; then
    echo '  requests without the required flags:'
    cat "${FIXTURE_DIR}/violations"
    return 1
  fi
}

# Runs install.sh with the assignments after $2 and checks that it fails as last_run_failed describes for $1 and $2,
# leaving the installed binary, the packages, and the temporary directory as they were.
rejected() {
  rejected_message="$1"
  rejected_requests="$2"
  shift 2
  run_installer "$@"
  if ! last_run_failed "${rejected_message}" "${rejected_requests}" \
    || ! [ "$(target_state)" = "${baseline_target}" ] \
    || ! [ "$(packages_state)" = "${baseline_packages}" ] \
    || ! no_install_leftovers; then
    echo '  (the binary, packages, and leftovers are compared with the state before the case)'
    show_run
    return 1
  fi
}

accepted_forms="a release version MAJOR.MINOR.PATCH"
reset_serve
check "a two-part version is rejected before any request" rejected "${accepted_forms}" none VERSION=1.15
check "a branch name is rejected before any request" rejected "${accepted_forms}" none VERSION=main
check "a pre-release version is rejected before any request" rejected "${accepted_forms}" none VERSION=1.12.0-alpha1
check "a version with a leading zero is rejected before any request" rejected "${accepted_forms}" none VERSION=1.07.0
check "an empty version is rejected before any request" rejected "${accepted_forms}" none VERSION=
check "a version below the minimum is rejected naming 1.7.0" rejected "below the minimum 1.7.0" none VERSION=1.6.6
check "an unsupported architecture is rejected naming it" \
  rejected 'unsupported architecture "riscv64"' none PATH="${FIXTURE_DIR}/uname:${FIXTURE_DIR}/bin:${PATH}"

mv /etc/os-release /etc/os-release.saved
check "a missing /etc/os-release is rejected" rejected "/etc/os-release is missing" none
printf 'ID=gentoo\n' >/etc/os-release
check "an unsupported distribution is rejected naming it" rejected 'unsupported distribution "gentoo"' none
rm -f /etc/os-release
mv /etc/os-release.saved /etc/os-release

mv /usr/bin/apt-get /usr/bin/apt-get.hidden
check "a supported family without apt-get is rejected naming the package manager" \
  rejected "its package manager apt-get is missing" none
mv /usr/bin/apt-get.hidden /usr/bin/apt-get

# A directory at the target: the target differs from the baseline while it is there, so this case checks the
# directory and the baseline only after putting the file back.
directory_at_target() {
  mv "${TARGET}" "${FIXTURE_DIR}/moved"
  mkdir "${TARGET}"
  run_installer VERSION=1.7.0
  directory_at_ok=true
  last_run_failed "${TARGET} exists but is not a regular file" none || directory_at_ok=false
  if [ ! -d "${TARGET}" ] || [ -n "$(ls -A "${TARGET}")" ]; then
    printf '  %s is no longer an empty directory\n' "${TARGET}"
    directory_at_ok=false
  fi
  rmdir "${TARGET}"
  mv "${FIXTURE_DIR}/moved" "${TARGET}"
  [ "$(target_state)" = "${baseline_target}" ] || directory_at_ok=false
  no_install_leftovers || directory_at_ok=false
  if [ "${directory_at_ok}" = "false" ]; then
    show_run
    return 1
  fi
}
check "a directory at /usr/local/bin/packer fails the install before any request and is left as it was" \
  directory_at_target

# The Checkpoint answer, with version latest. The release is served whole, so only the answer can fail the install.
serve_real_release
check "an unreachable Checkpoint service fails naming its URL before any checksum list" \
  rejected "cannot read https://${CHECKPOINT}" SHA256SUMS
serve_checkpoint '{"product":"packer","alerts":[]}'
check "a Checkpoint answer without a current version fails before any checksum list" \
  rejected "names no current_version" SHA256SUMS
serve_checkpoint '{"product":"packer","current_version":"1.7.0","current_version":"1.7.0","alerts":[]}'
check "a Checkpoint answer with two current versions fails before any checksum list" \
  rejected "names more than one current_version" SHA256SUMS
serve_checkpoint '{"product":"packer","current_version":"1.12.0-alpha1","alerts":[]}'
check "a Checkpoint answer naming a pre-release fails before any checksum list, naming it" \
  rejected 'the current version is "1.12.0-alpha1"' SHA256SUMS
serve_checkpoint '{"product":"packer","current_version":"1.6.6","alerts":[]}'
check "a Checkpoint answer naming a version below the minimum fails before any checksum list, naming it" \
  rejected 'the current version is "1.6.6"' SHA256SUMS
serve_checkpoint '{"product":"packer","current_version":"","alerts":[]}'
check "a Checkpoint answer naming an empty version fails before any checksum list" \
  rejected 'the current version is ""' SHA256SUMS
serve_checkpoint '{"product":"packer","current_version":"1.7.0","alerts":[]}'
serve_redirect "${CHECKPOINT}"
check "a Checkpoint answer that is a redirect fails before any checksum list" \
  rejected "answered with HTTP status 302" SHA256SUMS

reset_serve
check "a release that does not exist fails naming the version" \
  rejected "check that release 1.99.0 exists" .zip VERSION=1.99.0
serve_release "${fixtures}/hashicorp.asc" "${fixtures}/sums-1.7.0" "" "${fixtures}/${archive_name}"
check "a release without a signature file fails verification before the archive is requested" \
  rejected "verification failed: cannot download" .zip VERSION=1.7.0
serve_release "" "${fixtures}/sums-1.7.0" "${fixtures}/sums-1.7.0.sig" "${fixtures}/${archive_name}"
check "an unreachable key fails naming its URL" rejected "cannot download https://${KEY}" .zip VERSION=1.7.0
serve_release "${fixtures}/hashicorp.asc" "${fixtures}/altered-1.7.0" "${fixtures}/sums-1.7.0.sig" \
  "${fixtures}/${archive_name}"
check "a checksum list altered by one byte fails verification before the archive is requested" \
  rejected "verification failed" .zip VERSION=1.7.0
serve_release "${fixtures}/key-with-other.asc" "${fixtures}/sums-1.7.0" "${fixtures}/sums-1.7.0.other-sig" \
  "${fixtures}/${archive_name}"
check "a list signed by another key in the key file fails verification" \
  rejected "not by the release key ${FINGERPRINT}" .zip VERSION=1.7.0
serve_release "${fixtures}/hashicorp.asc" "${fixtures}/sums-1.7.1" "${fixtures}/sums-1.7.1.sig" \
  "${fixtures}/${archive_name}"
check "a signed list without an entry for the archive fails before the archive is requested" \
  rejected "holds no entry for ${archive_name}" .zip VERSION=1.7.0
serve_release "${fixtures}/hashicorp.asc" "${fixtures}/sums-1.7.0" "${fixtures}/sums-1.7.0.sig" "${fixtures}/fake.zip"
check "an archive that does not match its entry fails verification" \
  rejected "does not match its entry in the checksum list" any VERSION=1.7.0
serve_release "${fixtures}/hashicorp.asc" "${fixtures}/sums-1.7.0" "${fixtures}/sums-1.7.0.sig" ""
check "a release without the archive fails naming its URL" \
  rejected "cannot download https://${RELEASES}/1.7.0/${archive_name}" any VERSION=1.7.0
serve_real_release
serve_redirect "${RELEASES}/1.7.0/packer_1.7.0_SHA256SUMS"
check "a checksum list answered with a redirect fails before the archive is requested" \
  rejected "answered with HTTP status 302" .zip VERSION=1.7.0
serve_real_release
serve_redirect "${RELEASES}/1.7.0/${archive_name}"
check "an archive answered with a redirect fails the install" \
  rejected "answered with HTTP status 302" any VERSION=1.7.0

same_release_kept() {
  reset_serve
  same_release_before="$(stat -c '%i %Y' "${TARGET}")"
  run_installer VERSION="${installed_version}"
  if [ "${run_status}" -ne 0 ] || [ -s "${FIXTURE_DIR}/requests" ] \
    || [ "$(stat -c '%i %Y' "${TARGET}")" != "${same_release_before}" ]; then
    echo '  expected success, no request, and an unchanged binary'
    show_run
    return 1
  fi
}
check "the installed release requested again is kept without any request" same_release_kept

# With version latest and a Checkpoint answer naming 1.7.0, so the fixtures also cover the path a default install
# takes.
unreadable_replaced() {
  printf '#!/bin/sh\nexit 1\n' >"${FIXTURE_DIR}/stand-in"
  chmod 0755 "${FIXTURE_DIR}/stand-in"
  replace_target "${FIXTURE_DIR}/stand-in"
  serve_real_release
  serve_checkpoint '{"product":"packer","current_version":"1.7.0","alerts":[]}'
  run_installer
  if [ "${run_status}" -ne 0 ] || [ -s "${FIXTURE_DIR}/violations" ]; then
    show_run
    return 1
  fi
  packer_reports_version 1.7.0 && no_install_leftovers
}
check "an installed packer that exits 1 is replaced by the release the Checkpoint answer names" unreadable_replaced

latest_kept_without_download() {
  latest_kept_before="$(stat -c '%i %Y' "${TARGET}")"
  run_installer
  if [ "${run_status}" -ne 0 ] || grep -q -F -e SHA256SUMS -e .zip -e pgp-key "${FIXTURE_DIR}/requests" \
    || [ "$(stat -c '%i %Y' "${TARGET}")" != "${latest_kept_before}" ]; then
    echo '  expected success, only the Checkpoint request, and an unchanged binary'
    show_run
    return 1
  fi
}
check "the same release selected again through latest is kept without downloading a list, key, or archive" \
  latest_kept_without_download

reportResults
