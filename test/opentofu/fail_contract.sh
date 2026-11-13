#!/bin/sh
# Scenario fail_contract: debian:12 with the default option. Runs install.sh itself against local fixtures served by a
# curl stand-in, to check option and platform rejection, the target check, latest-release handling, transport
# failures, signature and checksum verification, the same release without a download, and the replacement of an
# unreadable binary. Every rejected run must leave the installed tofu, the packages, and the temporary directory as they
# were. The build's binary is restored at the end. POSIX sh, like the other opentofu tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

test_dir="$(cd "$(dirname "$0")" && pwd)"
installer="${test_dir}/_feature/install.sh"
readonly TARGET="/usr/local/bin/tofu"
readonly DOWNLOAD="github.com/opentofu/opentofu/releases/download"
readonly KEY="get.opentofu.org/opentofu.asc"
readonly FINGERPRINT="E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
esac
archive_name="tofu_1.6.3_linux_${arch}.tar.gz"
# Saved before it is cut to the first line, so a failing tofu stops the script here instead of hiding in a pipeline.
installed_version="$(isolated_tofu version)"
installed_version="$(printf '%s\n' "${installed_version}" | sed -n 1p)"
installed_version="${installed_version#OpenTofu v}"

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
cp -p "${TARGET}" "${FIXTURE_DIR}/original/tofu"
restore() {
  if [ -e /usr/bin/apt-get.hidden ]; then mv /usr/bin/apt-get.hidden /usr/bin/apt-get; fi
  if [ -e /etc/os-release.saved ] || [ -L /etc/os-release.saved ]; then
    rm -f /etc/os-release
    mv /etc/os-release.saved /etc/os-release
  fi
  rm -rf "${TARGET}"
  cp -p "${FIXTURE_DIR}/original/tofu" "${TARGET}"
  rm -rf "${FIXTURE_DIR}"
}
trap restore EXIT

# Replaces ${TARGET} with file $1 by a rename next to it, never by writing into it: writing into an executable that has
# just run can fail with "Text file busy".
replace_target() {
  cp -p "$1" /usr/local/bin/.fixture-replacement
  mv -f /usr/local/bin/.fixture-replacement "${TARGET}"
}

# Preparation, before the baselines: the real key, the signed lists of 1.6.3 and 1.6.0 (whose Linux archives are zip
# only), and the real 1.6.3 archive, fetched with the real curl; and gpg-agent, which only this script needs, to make a
# key that is not upstream's.
real_fetch() {
  /usr/bin/curl --proto '=https' --proto-redir '=https' --location --fail --silent --show-error --retry 3 \
    --output "$1" "$2"
}
real_fetch "${fixtures}/opentofu.asc" "https://${KEY}"
for release in 1.6.3 1.6.0; do
  real_fetch "${fixtures}/sums-${release}" "https://${DOWNLOAD}/v${release}/tofu_${release}_SHA256SUMS"
  real_fetch "${fixtures}/sums-${release}.gpgsig" "https://${DOWNLOAD}/v${release}/tofu_${release}_SHA256SUMS.gpgsig"
done
real_fetch "${fixtures}/${archive_name}" "https://${DOWNLOAD}/v1.6.3/${archive_name}"
printf 'not an OpenTofu archive\n' >"${fixtures}/fake.tar.gz"
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
other_gpg --import "${fixtures}/opentofu.asc"
other_gpg --armor --export >"${fixtures}/key-with-other.asc"
other_gpg --output "${fixtures}/sums-1.6.3.other-gpgsig" --detach-sign "${fixtures}/sums-1.6.3"
gpgconf --homedir "${other_home}" --kill gpg-agent

# A list derived from the real one: one byte of a checksum changed after signing.
sed '5s/^./0/' "${fixtures}/sums-1.6.3" >"${fixtures}/altered-1.6.3"

# Serves nothing; each case then serves what it needs.
reset_serve() {
  rm -rf "${FIXTURE_DIR}/serve"
  mkdir -p "${FIXTURE_DIR}/serve/${DOWNLOAD}/v1.6.3" "${FIXTURE_DIR}/serve/${KEY%/*}" \
    "${FIXTURE_DIR}/serve/github.com/opentofu/opentofu/releases"
}
serve() {
  cp "$1" "${FIXTURE_DIR}/serve/$2"
}
# Serves the key $1, the list $2 with signature $3, and archive $4 as release 1.6.3; an empty argument serves nothing
# in its place.
serve_release() {
  reset_serve
  if [ -n "$1" ]; then serve "$1" "${KEY}"; fi
  if [ -n "$2" ]; then serve "$2" "${DOWNLOAD}/v1.6.3/tofu_1.6.3_SHA256SUMS"; fi
  if [ -n "$3" ]; then serve "$3" "${DOWNLOAD}/v1.6.3/tofu_1.6.3_SHA256SUMS.gpgsig"; fi
  if [ -n "$4" ]; then serve "$4" "${DOWNLOAD}/v1.6.3/${archive_name}"; fi
}
# Makes the latest-release link redirect to $1.
serve_latest() {
  reset_serve
  printf '%s' "$1" >"${FIXTURE_DIR}/serve/github.com/opentofu/opentofu/releases/latest.location"
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
check "a two-part version is rejected before any request" rejected "${accepted_forms}" none VERSION=1.13
check "a branch name is rejected before any request" rejected "${accepted_forms}" none VERSION=main
check "a pre-release version is rejected before any request" rejected "${accepted_forms}" none VERSION=1.13.0-rc1
check "a version with a leading zero is rejected before any request" rejected "${accepted_forms}" none VERSION=1.06.3
check "a version below the minimum is rejected naming 1.6.3" rejected "below the minimum 1.6.3" none VERSION=1.6.2
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
  run_installer VERSION=1.6.3
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
check "a directory at /usr/local/bin/tofu fails the install before any request and is left as it was" \
  directory_at_target

serve_latest "https://github.com/opentofu/opentofu/releases/tag/v1.14.0-beta1"
check "a latest-release link to a pre-release tag fails before any checksum list, naming the tag" \
  rejected 'the latest release is "v1.14.0-beta1"' SHA256SUMS
serve_latest "http://github.com/opentofu/opentofu/releases/tag/v1.6.3"
check "a latest-release link redirecting to a plain HTTP URL fails before any checksum list" \
  rejected 'redirects to "http://github.com/opentofu/opentofu/releases/tag/v1.6.3"' SHA256SUMS
serve_latest "https://example.invalid/opentofu/releases/tag/v1.6.3"
check "a latest-release link redirecting to another host fails before any checksum list" \
  rejected "not to a release page under https://github.com/opentofu/opentofu/releases/tag/" SHA256SUMS
# An owner name GitHub cannot register (it starts and ends with "-"), so it names no real account.
serve_latest "https://github.com/-not-opentofu-/opentofu/releases/tag/v1.6.3"
check "a latest-release link redirecting to another repository on github.com fails before any checksum list" \
  rejected "not to a release page under https://github.com/opentofu/opentofu/releases/tag/" SHA256SUMS
reset_serve
touch "${FIXTURE_DIR}/serve/github.com/opentofu/opentofu/releases/latest"
check "a latest-release link that does not redirect fails before any checksum list" \
  rejected "did not redirect to a release" SHA256SUMS

reset_serve
check "a release that does not exist fails naming the version" \
  rejected "check that release v1.99.0 exists" .tar.gz VERSION=1.99.0
serve_release "${fixtures}/opentofu.asc" "${fixtures}/sums-1.6.3" "" "${fixtures}/${archive_name}"
check "a release without a signature file fails verification before the archive is requested" \
  rejected "verification failed: cannot download" .tar.gz VERSION=1.6.3
serve_release "" "${fixtures}/sums-1.6.3" "${fixtures}/sums-1.6.3.gpgsig" "${fixtures}/${archive_name}"
check "an unreachable key fails naming its URL" rejected "cannot download https://${KEY}" .tar.gz VERSION=1.6.3
serve_release "${fixtures}/opentofu.asc" "${fixtures}/altered-1.6.3" "${fixtures}/sums-1.6.3.gpgsig" \
  "${fixtures}/${archive_name}"
check "a checksum list altered by one byte fails verification before the archive is requested" \
  rejected "verification failed" .tar.gz VERSION=1.6.3
serve_release "${fixtures}/key-with-other.asc" "${fixtures}/sums-1.6.3" "${fixtures}/sums-1.6.3.other-gpgsig" \
  "${fixtures}/${archive_name}"
check "a list signed by another key in the key file fails verification" \
  rejected "not by the release key ${FINGERPRINT}" .tar.gz VERSION=1.6.3
serve_release "${fixtures}/opentofu.asc" "${fixtures}/sums-1.6.0" "${fixtures}/sums-1.6.0.gpgsig" \
  "${fixtures}/${archive_name}"
check "a signed list without an entry for the archive fails before the archive is requested" \
  rejected "holds no entry for ${archive_name}" .tar.gz VERSION=1.6.3
serve_release "${fixtures}/opentofu.asc" "${fixtures}/sums-1.6.3" "${fixtures}/sums-1.6.3.gpgsig" \
  "${fixtures}/fake.tar.gz"
check "an archive that does not match its entry fails verification" \
  rejected "does not match its entry in the checksum list" any VERSION=1.6.3
serve_release "${fixtures}/opentofu.asc" "${fixtures}/sums-1.6.3" "${fixtures}/sums-1.6.3.gpgsig" ""
check "a release without the archive fails naming its URL" \
  rejected "cannot download https://${DOWNLOAD}/v1.6.3/${archive_name}" any VERSION=1.6.3

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

unreadable_replaced() {
  printf '#!/bin/sh\nexit 1\n' >"${FIXTURE_DIR}/stand-in"
  chmod 0755 "${FIXTURE_DIR}/stand-in"
  replace_target "${FIXTURE_DIR}/stand-in"
  serve_release "${fixtures}/opentofu.asc" "${fixtures}/sums-1.6.3" "${fixtures}/sums-1.6.3.gpgsig" \
    "${fixtures}/${archive_name}"
  run_installer VERSION=1.6.3
  if [ "${run_status}" -ne 0 ] || [ -s "${FIXTURE_DIR}/violations" ]; then
    show_run
    return 1
  fi
  tofu_reports_version 1.6.3 && no_install_leftovers
}
check "an installed tofu that exits 1 is replaced by the requested release" unreadable_replaced

reportResults
