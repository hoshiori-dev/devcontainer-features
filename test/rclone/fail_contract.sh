#!/bin/sh
# Scenario fail_contract: debian:12 with default options. Runs install.sh itself against local fixtures served by a
# curl stand-in, to check option and platform rejection, target checks, version-file handling, transport failures,
# signature and checksum verification, the same release without a download, and the replacement of an unreadable
# binary. Every rejected run must leave the installed rclone, its completion files, the packages, and the temporary
# directory as they were. The build's installation is restored at the end. POSIX sh, like the other rclone tests.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

test_dir="$(cd "$(dirname "$0")" && pwd)"
installer="${test_dir}/_feature/install.sh"
readonly TARGET="/usr/local/bin/rclone"
readonly ZSH_TARGET="/usr/local/share/zsh/site-functions/_rclone"
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
esac
archive_name="rclone-v1.70.0-linux-${arch}.zip"
installed_version="$(isolated_rclone version | sed -n 1p)"
installed_version="${installed_version#rclone v}"

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR
fixtures="${FIXTURE_DIR}/fixtures"
mkdir -p "${fixtures}" "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/uname" "${FIXTURE_DIR}/weak-gpg" \
  "${FIXTURE_DIR}/original"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
# shellcheck disable=SC2016 # The stand-ins' own parameters, expanded when they run.
printf '#!/bin/sh\nif [ "${1-}" = -m ]; then echo riscv64; else exec /usr/bin/uname "$@"; fi\n' \
  >"${FIXTURE_DIR}/uname/uname"
# shellcheck disable=SC2016 # The stand-in's own parameters, expanded when it runs.
printf '#!/bin/sh\nexec /usr/bin/gpg --weak-digest SHA1 "$@"\n' >"${FIXTURE_DIR}/weak-gpg/gpg"
chmod +x "${FIXTURE_DIR}/bin/curl" "${FIXTURE_DIR}/uname/uname" "${FIXTURE_DIR}/weak-gpg/gpg"
touch "${FIXTURE_DIR}/requests" "${FIXTURE_DIR}/violations"

# The build's binary and completion files, restored at the end whatever the cases did to them.
cp -p "${TARGET}" "${FIXTURE_DIR}/original/rclone"
for completion in ${RCLONE_COMPLETIONS}; do cp -p "${completion}" "${FIXTURE_DIR}/original/${completion##*/}"; done
restore() {
  if [ -e /usr/bin/apt-get.hidden ]; then mv /usr/bin/apt-get.hidden /usr/bin/apt-get; fi
  if [ -e /etc/os-release.saved ] || [ -L /etc/os-release.saved ]; then
    rm -f /etc/os-release
    mv /etc/os-release.saved /etc/os-release
  fi
  rm -rf "${TARGET}" "${ZSH_TARGET}"
  cp -p "${FIXTURE_DIR}/original/rclone" "${TARGET}"
  for restore_completion in ${RCLONE_COMPLETIONS}; do
    cp -p "${FIXTURE_DIR}/original/${restore_completion##*/}" "${restore_completion}"
  done
  rm -rf "${FIXTURE_DIR}"
}
trap restore EXIT

# Preparation, before the baselines: the real key list, two releases' signed lists, and one real archive, fetched with
# the real curl; and gpg-agent, which only this script needs, to make a key that is not upstream's.
real_fetch() {
  /usr/bin/curl --proto '=https' --fail --silent --show-error --retry 3 --output "$1" "$2"
}
real_fetch "${fixtures}/KEYS" https://rclone.org/KEYS
real_fetch "${fixtures}/sums-1.70.0" https://downloads.rclone.org/v1.70.0/SHA256SUMS
real_fetch "${fixtures}/sums-1.63.0" https://downloads.rclone.org/v1.63.0/SHA256SUMS
real_fetch "${fixtures}/${archive_name}" "https://downloads.rclone.org/v1.70.0/${archive_name}"
printf 'not an rclone archive\n' >"${fixtures}/fake.zip"
DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends gpg-agent >/dev/null
rm -rf /var/lib/apt/lists/*

other_home="${FIXTURE_DIR}/other-gnupg"
mkdir -m 700 "${other_home}"
other_gpg() {
  gpg --batch --quiet --homedir "${other_home}" --pinentry-mode loopback --passphrase '' "$@"
}
other_gpg --quick-gen-key 'Fixture signer <fixture@example.invalid>' ed25519 sign never
other_gpg --import "${fixtures}/KEYS"
other_gpg --armor --export >"${fixtures}/KEYS-with-other"
other_gpg --output "${fixtures}/plain-1.70.0" --decrypt "${fixtures}/sums-1.70.0" 2>/dev/null
other_gpg --output "${fixtures}/other-signed-1.70.0" --clearsign "${fixtures}/plain-1.70.0"
gpgconf --homedir "${other_home}" --kill gpg-agent

# Fixture lists derived from the real ones: one byte of a checksum changed inside the signed text; and release
# 1.63.0's signed list followed by an entry for the 1.70.0 archive outside the signature block.
sed '5s/^./0/' "${fixtures}/sums-1.70.0" >"${fixtures}/altered-1.70.0"
cp "${fixtures}/sums-1.63.0" "${fixtures}/outside-1.70.0"
printf '%s  %s\n' "$(sha256sum <"${fixtures}/fake.zip" | cut -d ' ' -f 1)" "${archive_name}" \
  >>"${fixtures}/outside-1.70.0"

# Serves nothing; each case then serves what it needs.
reset_serve() {
  rm -rf "${FIXTURE_DIR}/serve"
  mkdir -p "${FIXTURE_DIR}/serve/downloads.rclone.org/v1.70.0" "${FIXTURE_DIR}/serve/rclone.org"
}
serve() {
  cp "$1" "${FIXTURE_DIR}/serve/$2"
}
serve_release() {
  reset_serve
  serve "${fixtures}/KEYS" rclone.org/KEYS
  serve "$1" downloads.rclone.org/v1.70.0/SHA256SUMS
  if [ -n "$2" ]; then serve "$2" "downloads.rclone.org/v1.70.0/${archive_name}"; fi
}

targets_state() {
  for targets_state_path in "${TARGET}" ${RCLONE_COMPLETIONS}; do
    if [ -f "${targets_state_path}" ]; then
      printf '%s %s\n' "$(sha256sum <"${targets_state_path}")" "$(stat -c '%i %Y' "${targets_state_path}")"
    else
      printf 'not a regular file: %s\n' "${targets_state_path}"
    fi
  done
}
packages_state() {
  dpkg-query --show --showformat '${Package} ${Version}\n'
}
baseline_targets="$(targets_state)"
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
# leaving the installed files, the packages, and the temporary directory as they were.
rejected() {
  rejected_message="$1"
  rejected_requests="$2"
  shift 2
  run_installer "$@"
  if ! last_run_failed "${rejected_message}" "${rejected_requests}" \
    || ! [ "$(targets_state)" = "${baseline_targets}" ] \
    || ! [ "$(packages_state)" = "${baseline_packages}" ] \
    || ! no_install_leftovers; then
    echo '  (targets, packages, and leftovers are compared with the state before the case)'
    show_run
    return 1
  fi
}

accepted_forms="a release version MAJOR.MINOR.PATCH"
reset_serve
check "a two-part version is rejected before any request" rejected "${accepted_forms}" none VERSION=1.70
check "a branch name is rejected before any request" rejected "${accepted_forms}" none VERSION=master
check "a beta build's version is rejected before any request" \
  rejected "${accepted_forms}" none VERSION=1.77.0-beta.10751.d459c3f99
check "a version below the minimum is rejected naming 1.63.0" rejected "below the minimum 1.63.0" none VERSION=1.62.2
check "an installMountDependencies value other than true or false is rejected" \
  rejected "option installMountDependencies" none INSTALLMOUNTDEPENDENCIES=maybe
check "an unsupported architecture is rejected naming it" \
  rejected 'unsupported architecture "riscv64"' none PATH="${FIXTURE_DIR}/uname:${FIXTURE_DIR}/bin:${PATH}"

mv /etc/os-release /etc/os-release.saved
check "a missing /etc/os-release is rejected" rejected "/etc/os-release is missing" none
printf 'ID=arch\n' >/etc/os-release
check "an unsupported distribution is rejected naming it" rejected 'unsupported distribution "arch"' none
rm -f /etc/os-release
mv /etc/os-release.saved /etc/os-release

mv /usr/bin/apt-get /usr/bin/apt-get.hidden
check "a supported family without apt-get is rejected naming the package manager" \
  rejected "its package manager apt-get is missing" none
mv /usr/bin/apt-get.hidden /usr/bin/apt-get

# A directory at a target: the targets differ from the baseline while it is there, so this case checks the directory
# and the baseline only after putting the file back.
directory_at() {
  mv "$1" "${FIXTURE_DIR}/moved"
  mkdir "$1"
  run_installer VERSION=1.70.0
  directory_at_ok=true
  last_run_failed "$1 exists but is not a regular file" none || directory_at_ok=false
  if [ ! -d "$1" ] || [ -n "$(ls -A "$1")" ]; then
    printf '  %s is no longer an empty directory\n' "$1"
    directory_at_ok=false
  fi
  rmdir "$1"
  mv "${FIXTURE_DIR}/moved" "$1"
  [ "$(targets_state)" = "${baseline_targets}" ] || directory_at_ok=false
  no_install_leftovers || directory_at_ok=false
  if [ "${directory_at_ok}" = "false" ]; then
    show_run
    return 1
  fi
}
check "a directory at /usr/local/bin/rclone fails the install before any request and is left as it was" \
  directory_at "${TARGET}"
check "a directory at a completion path fails the install before any request and is left as it was" \
  directory_at "${ZSH_TARGET}"

version_file() {
  reset_serve
  printf '%b' "$1" >"${FIXTURE_DIR}/serve/downloads.rclone.org/version.txt"
}
version_file '<html>not a version</html>\n'
check "a version file holding a page fails before any checksum list or archive, quoting it" \
  rejected 'holds "<html>not a version</html>"' SHA256SUMS
version_file 'rclone v1.62.0\n'
check "a version file naming a release below the minimum fails" rejected 'holds "rclone v1.62.0"' SHA256SUMS
version_file 'rclone v1.77.0-beta.10751.d459c3f99\n'
check "a version file naming a beta build fails" rejected 'holds "rclone v1.77.0-beta' SHA256SUMS
version_file 'rclone v1.70.0\nrclone v1.70.0\n'
check "a version file of two lines fails" rejected 'not one line' SHA256SUMS
reset_serve
touch "${FIXTURE_DIR}/serve/downloads.rclone.org/version.txt.redirect"
check "a redirect from the version file fails the install" \
  rejected "cannot download https://downloads.rclone.org/version.txt" SHA256SUMS

reset_serve
check "a release that does not exist fails naming the version" \
  rejected "check that release v1.99.0 exists" .zip VERSION=1.99.0
serve_release "${fixtures}/sums-1.70.0" "${fixtures}/${archive_name}"
rm "${FIXTURE_DIR}/serve/rclone.org/KEYS"
check "an unreachable key list fails naming its URL" rejected "cannot download https://rclone.org/KEYS" .zip \
  VERSION=1.70.0
serve_release "${fixtures}/altered-1.70.0" "${fixtures}/${archive_name}"
check "a signed text altered by one byte fails verification before the archive is requested" \
  rejected "verification failed" .zip VERSION=1.70.0
serve_release "${fixtures}/plain-1.70.0" "${fixtures}/${archive_name}"
check "an unsigned checksum list fails verification before the archive is requested" \
  rejected "verification failed" .zip VERSION=1.70.0
serve_release "${fixtures}/other-signed-1.70.0" "${fixtures}/${archive_name}"
serve "${fixtures}/KEYS-with-other" rclone.org/KEYS
check "a list signed by another key in the key list fails verification" \
  rejected "not by the release key FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA" .zip VERSION=1.70.0
serve_release "${fixtures}/sums-1.63.0" "${fixtures}/${archive_name}"
check "a signed list without an entry for the archive fails before the archive is requested" \
  rejected "holds no entry for ${archive_name}" .zip VERSION=1.70.0
serve_release "${fixtures}/outside-1.70.0" "${fixtures}/fake.zip"
check "an entry outside the signed text is not used" \
  rejected "holds no entry for ${archive_name}" .zip VERSION=1.70.0
serve_release "${fixtures}/sums-1.70.0" "${fixtures}/fake.zip"
check "an archive that does not match its signed entry fails verification" \
  rejected "does not match its entry in the signed SHA256SUMS" any VERSION=1.70.0
serve_release "${fixtures}/sums-1.70.0" ""
check "a release without the archive fails naming its URL" \
  rejected "cannot download https://downloads.rclone.org/v1.70.0/${archive_name}" any VERSION=1.70.0
serve_release "${fixtures}/sums-1.70.0" "${fixtures}/${archive_name}"
check "a GnuPG that refuses SHA-1 signatures fails verification without a fallback" \
  rejected "verification failed" .zip VERSION=1.70.0 PATH="${FIXTURE_DIR}/weak-gpg:${FIXTURE_DIR}/bin:${PATH}"

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
  printf '#!/bin/sh\nexit 1\n' >"${TARGET}"
  serve_release "${fixtures}/sums-1.70.0" "${fixtures}/${archive_name}"
  run_installer VERSION=1.70.0
  if [ "${run_status}" -ne 0 ] || [ -s "${FIXTURE_DIR}/violations" ]; then
    show_run
    return 1
  fi
  rclone_reports_version 1.70.0 && completions_match && no_install_leftovers
}
check "an installed rclone that exits 1 is replaced by the requested release" unreadable_replaced

reportResults
