#!/usr/bin/env bash
# Scenario "fail_install": the CLI installed lxc-distrobuilder on debian:12 with default options. The script runs the
# installer again behind a `curl` stand-in (fixture_curl.sh) that records every request and answers some of them from
# local fixtures. It checks that option and platform rejections happen before any request ("Malformed version",
# "Version below the minimum", "Unsupported distribution", "Unsupported architecture"); that the installed release is
# not downloaded again ("Same release twice"); how the latest-release link is read ("Latest-release link to an
# unusable tag"); and that a missing release, a signature that is missing, wrong, or made by another key, and a Go
# archive that does not match its checksum each fail the install and leave the installed executable as it was.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

readonly SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly RELEASES="github.com/lxc/distrobuilder/releases"
readonly KEY="github.com/stgraber.gpg"
readonly FINGERPRINT="602F567663E593BCBD14F338C638974D64792D67"
# An earlier release than the installed one, whose real archive and signature the cases alter, and three versions
# that have no release.
readonly EARLIER="3.3.1"
readonly FAKE="99.1.0"
readonly ABSENT="99.0.0"
readonly RENAMED="99.2.0"

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
esac
test_dir="$(cd "$(dirname "$0")" && pwd)"
installed="$(cat "${DB_VERSION_FILE}")"

FIXTURE_DIR="$(mktemp -d)"
readonly FIXTURE_DIR
readonly SERVE="${FIXTURE_DIR}/serve"
readonly LATEST_LOCATION="${SERVE}/${RELEASES}/latest.location"
mkdir -p "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/dpkg" "${SERVE}/${RELEASES}/download" "${SERVE}/dl.google.com/go"
mkdir -m 700 "${FIXTURE_DIR}/gnupg"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
# A `dpkg` that names another architecture and hands every other call to the real dpkg.
cat >"${FIXTURE_DIR}/dpkg/dpkg" <<'STAND_IN'
#!/bin/sh
if [ "${1-}" = --print-architecture ]; then
  echo riscv64
else
  exec /usr/bin/dpkg "$@"
fi
STAND_IN
chmod +x "${FIXTURE_DIR}/bin/curl" "${FIXTURE_DIR}/dpkg/dpkg"
chmod a+rx "${FIXTURE_DIR}"
touch "${FIXTURE_DIR}/requests" "${FIXTURE_DIR}/violations"
chmod a+rw "${FIXTURE_DIR}/requests" "${FIXTURE_DIR}/violations"

# The state every rejected run must leave as it was: the executable, the version record, the installed packages, and
# the names in /usr/local/bin.
state() {
  sha256sum "${DB_TARGET}" "${DB_VERSION_FILE}"
  dpkg-query -W -f='${Package} ${Version}\n' | sha256sum
  ls -a /usr/local/bin
}

# Runs the installer behind the stand-in with the given NAME=value options, sets ${output} and ${status}, and shows
# the end of the output. The requests of the run are in ${FIXTURE_DIR}/requests.
run() {
  : >"${FIXTURE_DIR}/requests"
  status=0
  output="$(as_root env -i PATH="${FIXTURE_DIR}/bin:${SYSTEM_PATH}" HOME=/root FIXTURE_DIR="${FIXTURE_DIR}" "$@" \
    bash "${test_dir}/_feature/install.sh" 2>&1)" || status=$?
  printf '%s\n' "${output}" | tail -n 12
}

# The last run failed, its output matches the pattern $1, and the installed state is as before.
rejected_with() {
  ((status != 0)) || return
  grep -q -E "$1" <<<"${output}" || return
  [[ "$(state)" == "${state_before}" ]]
}

# The last run succeeded and reported the release $1 as already installed.
recognized_as_installed() {
  ((status == 0)) || return
  grep -q "distrobuilder $1 is already installed" <<<"${output}"
}

# The last run made no request at all.
no_request() {
  [[ ! -s "${FIXTURE_DIR}/requests" ]]
}

# The last run requested no release asset and no Go archive.
no_download() {
  ! grep -q -E '/releases/download/|dl\.google\.com' "${FIXTURE_DIR}/requests"
}

state_before="$(state)"
status=0
output=""

for value in 3.4 main 3.5.0-rc1 03.4.0 ''; do
  run VERSION="${value}"
  check "Malformed version \"${value}\": the install fails naming the accepted forms" \
    rejected_with 'option version is ".*"; use "latest" or a release version MAJOR.MINOR.PATCH'
  check "Malformed version \"${value}\": nothing was requested" no_request
done

for value in 3.2.0 3.3.0 v3.3.0; do
  run VERSION="${value}"
  check "Version below the minimum ${value}: the install fails naming 3.3.1" \
    rejected_with 'below the minimum 3\.3\.1; set version to 3\.3\.1 or later'
  check "Version below the minimum ${value}: nothing was requested" no_request
done

run VMSUPPORT=yes
check "an invalid vmSupport fails the install naming the accepted values" \
  rejected_with 'option vmSupport is "yes"; use true or false'
run WINDOWSSUPPORT=1
check "an invalid windowsSupport fails the install naming the accepted values" \
  rejected_with 'option windowsSupport is "1"; use true or false'

cp /etc/os-release "${FIXTURE_DIR}/os-release"
printf '%s\n' 'ID=alpine' 'VERSION_ID=3.22' | as_root tee /etc/os-release >/dev/null
run
as_root cp "${FIXTURE_DIR}/os-release" /etc/os-release
check "Unsupported distribution: the install fails naming the detected distribution" \
  rejected_with 'unsupported distribution "alpine"'
check "Unsupported distribution: nothing was requested" no_request

: >"${FIXTURE_DIR}/requests"
status=0
output="$(as_root env -i PATH="${FIXTURE_DIR}/dpkg:${FIXTURE_DIR}/bin:${SYSTEM_PATH}" HOME=/root \
  FIXTURE_DIR="${FIXTURE_DIR}" bash "${test_dir}/_feature/install.sh" 2>&1)" || status=$?
printf '%s\n' "${output}"
check "Unsupported architecture: the install fails naming the detected architecture" \
  rejected_with 'unsupported architecture "riscv64"'
check "Unsupported architecture: nothing was requested" no_request

run VERSION="${installed}"
check "Same release twice: the install succeeds and reports the release as installed" \
  recognized_as_installed "${installed}"
check "Same release twice: nothing was requested" no_request
check "Same release twice: the installed state is as before" test "$(state)" = "${state_before}"

run VERSION="v${installed}"
check "Leading v accepted: the installed release is recognized" recognized_as_installed "${installed}"

printf 'https://%s/tag/v%s' "${RELEASES}" "${installed}" >"${LATEST_LOCATION}"
run
check "Resolving latest: the release the redirect names is recognized as installed" \
  recognized_as_installed "${installed}"
check "Resolving latest: only the latest-release link was requested" \
  test "$(cat "${FIXTURE_DIR}/requests")" = "https://${RELEASES}/latest"

printf 'https://%s/tag/distrobuilder-3.2' "${RELEASES}" >"${LATEST_LOCATION}"
run
check "Latest-release link to an unusable tag: the install fails naming the tag" \
  rejected_with 'the latest release is "distrobuilder-3\.2", not a release version'
check "Latest-release link to an unusable tag: no archive was requested" no_download

printf 'https://github.com/example/other/releases/tag/v9.9.9' >"${LATEST_LOCATION}"
run
check "a latest-release link that leaves the repository fails the install" \
  rejected_with 'not to a release page under https://github.com/lxc/distrobuilder/releases/tag/'
check "a latest-release link that leaves the repository: no archive was requested" no_download
# Moved out of the served tree, so that the stand-in answers the link's HEAD request no longer.
mv "${LATEST_LOCATION}" "${FIXTURE_DIR}/latest.location.used"

mkdir -p "${SERVE}/${RELEASES}/download/v${ABSENT}"
touch "${SERVE}/${RELEASES}/download/v${ABSENT}/distrobuilder-${ABSENT}.tar.gz.missing"
run VERSION="${ABSENT}"
check "Release that does not exist: the install fails naming the version" \
  rejected_with "check that release ${ABSENT} exists"

# A source archive signed by a key made here stands in for a release signed by another key. Making a key needs
# gpg-agent, which the installer itself never uses.
as_root apt-get update >/dev/null
as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends gpg-agent >/dev/null
state_before="$(state)"
export GNUPGHOME="${FIXTURE_DIR}/gnupg"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-generate-key 'Stand-in signer' ed25519 sign never
fake_dir="${SERVE}/${RELEASES}/download/v${FAKE}"
mkdir -p "${fake_dir}" "${FIXTURE_DIR}/fake/distrobuilder-${FAKE}"
echo 'module example' >"${FIXTURE_DIR}/fake/distrobuilder-${FAKE}/go.mod"
tar -C "${FIXTURE_DIR}/fake" -czf "${fake_dir}/distrobuilder-${FAKE}.tar.gz" "distrobuilder-${FAKE}"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --armor --detach-sign \
  --output "${fake_dir}/distrobuilder-${FAKE}.tar.gz.asc" "${fake_dir}/distrobuilder-${FAKE}.tar.gz"

# The key file is upstream's own, fetched by the real curl: it does not hold the stand-in key.
run VERSION="${FAKE}"
check "Signature by another key, which the key file does not hold: verification fails" \
  rejected_with 'verification failed: the signature of .* does not verify'

# The key file holds the stand-in key beside upstream's.
/usr/bin/curl --fail --silent --location --output "${FIXTURE_DIR}/upstream.asc" "https://${KEY}"
gpg --batch --quiet --import "${FIXTURE_DIR}/upstream.asc"
mkdir -p "${SERVE}/github.com"
gpg --batch --armor --export >"${SERVE}/${KEY}"
run VERSION="${FAKE}"
check "Signature by another key, which the key file holds: verification fails naming the release key" \
  rejected_with "verification failed: .* is signed by [0-9A-F]{40}, not by the release key ${FINGERPRINT}"
mv "${SERVE}/${KEY}" "${FIXTURE_DIR}/both-keys.asc.used"
unset GNUPGHOME

touch "${fake_dir}/distrobuilder-${FAKE}.tar.gz.asc.missing"
run VERSION="${FAKE}"
check "Missing signature: verification fails" \
  rejected_with 'verification failed: cannot download .*\.tar\.gz\.asc, the signature of the source archive'

# Upstream's own archive of an earlier release, altered after signing, with upstream's signature.
earlier_dir="${SERVE}/${RELEASES}/download/v${EARLIER}"
mkdir -p "${earlier_dir}"
/usr/bin/curl --fail --silent --location --output "${FIXTURE_DIR}/earlier.tar.gz" \
  "https://${RELEASES}/download/v${EARLIER}/distrobuilder-${EARLIER}.tar.gz"
cp "${FIXTURE_DIR}/earlier.tar.gz" "${earlier_dir}/distrobuilder-${EARLIER}.tar.gz"
echo 'altered' >>"${earlier_dir}/distrobuilder-${EARLIER}.tar.gz"
run VERSION="${EARLIER}"
check "Invalid signature: an archive altered after signing fails verification" \
  rejected_with 'verification failed: the signature of .* does not verify'
mv "${earlier_dir}/distrobuilder-${EARLIER}.tar.gz" "${FIXTURE_DIR}/altered.tar.gz.used"

# Upstream's archive and signature of the earlier release, served under the name of another release: the signature
# is good and by the release key, and the archive is still not the release that was asked for.
other_dir="${SERVE}/${RELEASES}/download/v${RENAMED}"
mkdir -p "${other_dir}"
cp "${FIXTURE_DIR}/earlier.tar.gz" "${other_dir}/distrobuilder-${RENAMED}.tar.gz"
/usr/bin/curl --fail --silent --location --output "${other_dir}/distrobuilder-${RENAMED}.tar.gz.asc" \
  "https://${RELEASES}/download/v${EARLIER}/distrobuilder-${EARLIER}.tar.gz.asc"
run VERSION="${RENAMED}"
check "a validly signed archive of another release is not built in place of the selected one" \
  rejected_with "verification failed: .* outside distrobuilder-${RENAMED}/, so it is not the source of release"

# The Go archive that the earlier release's go.mod names, replaced by a stand-in that does not match upstream's
# published checksum, and then a checksum that cannot be fetched.
go_version="$(tar -xzOf "${FIXTURE_DIR}/earlier.tar.gz" "distrobuilder-${EARLIER}/go.mod" | sed -n 's/^go //p')"
go_archive="go${go_version}.linux-${arch}.tar.gz"
echo 'not a Go archive' >"${SERVE}/dl.google.com/go/${go_archive}"
run VERSION="${EARLIER}"
check "Digest mismatch: a Go archive that differs from the published checksum fails verification" \
  rejected_with "verification failed: ${go_archive} has the SHA-256 digest"
touch "${SERVE}/dl.google.com/go/${go_archive}.sha256.missing"
run VERSION="${EARLIER}"
check "Missing checksum: verification fails" \
  rejected_with "verification failed: cannot download .*${go_archive}\.sha256"

check "every request of the installer was HTTPS-only and failed on HTTP errors" test ! -s "${FIXTURE_DIR}/violations"
check "the installed distrobuilder still prints its recorded release" reports_version "${installed}"

reportResults
