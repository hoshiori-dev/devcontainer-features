#!/usr/bin/env bash
# Scenario fail_installation: godot installed with version 4.6 on debian:12, run as root. The script runs install.sh
# itself through installer.sh, with fixture_curl.sh serving fixture releases it builds, and checks what a successful
# image build cannot show: a matching installed version is skipped without a request; every failing run leaves
# /usr/local/bin/godot as it was and no residue, and a run that must fail before any change requests, installs, and
# changes nothing; an installed godot whose version cannot be read is replaced.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The architecture in the archive names, as install.sh derives it from uname -m.
ARCH=x86_64
if [[ "$(uname -m)" == aarch64 ]]; then ARCH=arm64; fi
readonly ARCH

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR

# zip builds the fixture archives. The real apt-get installs it before any stub is on PATH, and the package lists stay
# for reinstalling libfontconfig1 below.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends zip

cp -p "${TARGET}" "${FIXTURE_DIR}/godot.real"
cp -P /etc/os-release "${FIXTURE_DIR}/os-release"

# Puts back the image's /etc/os-release, a symbolic link on debian:12.
restore_os_release() {
  rm -f /etc/os-release
  cp -P "${FIXTURE_DIR}/os-release" /etc/os-release
}

# Puts back the godot the CLI installed, whatever a run or a preparation left at the target.
restore_real_godot() {
  rm -rf "${TARGET}"
  cp -p "${FIXTURE_DIR}/godot.real" "${TARGET}"
}

# Puts back what the script changes outside the fixture directory, and removes that directory, on every exit.
cleanup() {
  restore_os_release
  restore_real_godot
  rm -rf "${FIXTURE_DIR}"
}
trap cleanup EXIT

mkdir "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/riscv64"
cp "$(dirname "$0")/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
cat >"${FIXTURE_DIR}/bin/apt-get" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${FIXTURE_DIR}/apt-get.calls"
exit 1
STUB
# install.sh reads the machine architecture from uname -m.
printf '#!/bin/sh\necho riscv64\n' >"${FIXTURE_DIR}/riscv64/uname"
chmod 0755 "${FIXTURE_DIR}/bin/curl" "${FIXTURE_DIR}/bin/apt-get" "${FIXTURE_DIR}/riscv64/uname"
echo serve >"${FIXTURE_DIR}/mode"

# Builds release $1-stable under ${FIXTURE_DIR}/releases, replacing an earlier build: for x86_64 and arm64, an archive
# Godot_v<tag>_linux.<arch>.zip holding the executable Godot_v<tag>_linux.<arch>, a shell script that prints
# "$1.stable.official.0123456789" for --version, and SHA512-SUMS.txt with one entry per archive in sha512sum format.
# $2 names one defect: exits_nonzero (the executable prints that line but exits 1), other_version (it reports 4.6.2),
# extra_entry (the archives also hold README.txt), renamed_entry (their only entry is named godot), missing_entry and
# duplicate_entry (the list holds no entry or two for this machine's archive), digest_mismatch (the archives differ
# from their entries).
make_release() {
  local version="$1"
  local defect="${2-none}"
  local tag="${version}-stable"
  local release="${FIXTURE_DIR}/releases/${tag}"
  local build="${FIXTURE_DIR}/build"
  local reported="${version}.stable.official.0123456789"
  local exit_status=0
  local arch
  local executable
  local archive
  local entries
  case "${defect}" in
    exits_nonzero) exit_status=1 ;;
    other_version) reported="4.6.2.stable.official.0123456789" ;;
  esac
  rm -rf "${release}" "${build}"
  mkdir -p "${release}" "${build}"
  echo 'not part of a release' >"${build}/README.txt"
  for arch in x86_64 arm64; do
    executable="Godot_v${tag}_linux.${arch}"
    archive="Godot_v${tag}_linux.${arch}.zip"
    cat >"${build}/${executable}" <<EXECUTABLE
#!/bin/sh
# Fixture of the executable of Godot release ${tag}: answers --version only.
if [ "\$1" != --version ]; then exit 2; fi
echo ${reported}
exit ${exit_status}
EXECUTABLE
    chmod 0755 "${build}/${executable}"
    entries=("${executable}")
    case "${defect}" in
      extra_entry) entries+=(README.txt) ;;
      renamed_entry)
        mv "${build}/${executable}" "${build}/godot"
        entries=(godot)
        ;;
    esac
    (cd "${build}" && zip -q "${release}/${archive}" "${entries[@]}")
    if [[ "${defect}" == missing_entry && "${arch}" == "${ARCH}" ]]; then continue; fi
    (cd "${release}" && sha512sum "${archive}") >>"${release}/SHA512-SUMS.txt"
    if [[ "${defect}" == duplicate_entry && "${arch}" == "${ARCH}" ]]; then
      (cd "${release}" && sha512sum "${archive}") >>"${release}/SHA512-SUMS.txt"
    fi
    if [[ "${defect}" == digest_mismatch ]]; then echo tampered >>"${release}/${archive}"; fi
  done
}

# Version 4.6, given in each form that selects it, matches the godot the CLI installed.
identity="$(target_identity)"
for value in 4.6 4.6.0 4.6-stable; do
  run_installer "${value}"
  check "version ${value} with 4.6 installed: the install succeeds" succeeded
  check "version ${value} with 4.6 installed: /usr/local/bin/godot is left unchanged (inode and modification time)" \
    target_identity_is "${identity}"
  check "version ${value} with 4.6 installed: no archive is downloaded, and nothing else is requested" \
    requested_nothing
  check "version ${value} with 4.6 installed: no temporary directory or staged executable remains" no_install_residue
done

# The runs that must fail before any change find the font configuration library missing, as a fresh debian:12 does,
# so a run that reached the prerequisites would call the apt-get stub.
dpkg --remove libfontconfig1
linker_cache="$(ldconfig -p)"
if [[ "${linker_cache}" == *libfontconfig.so.1* ]]; then
  echo 'libfontconfig.so.1 is still known to the dynamic linker after removing libfontconfig1' >&2
  exit 1
fi

# Checks that the last run, named $1, which failed before any change, requested, installed, and left behind nothing.
checks_nothing_changed() {
  check "$1: nothing is downloaded or installed" nothing_downloaded_or_installed
  check "$1: /usr/local/bin/godot is left as it was before the install" godot_unchanged
  check "$1: no temporary directory or staged executable remains" no_install_residue
}

for value in 4 v4.7.2 4.7.2.1 4.06 master; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message naming the accepted forms" \
    failed_with 'use "latest" or a stable release MAJOR.MINOR or MAJOR.MINOR.PATCH'
  checks_nothing_changed "version ${value}"
done

for value in 4.8-beta2 4.7-rc1; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message saying that only stable releases are accepted" \
    failed_with 'only stable releases are accepted'
  checks_nothing_changed "version ${value}"
done

for value in 4.1.4 4.2 4.2.1; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message naming 4.2.2 as the minimum" failed_with 'the minimum 4.2.2'
  checks_nothing_changed "version ${value}"
done

run_installer latest "${FIXTURE_DIR}/riscv64"
check "architecture riscv64: the install fails with a message naming the architecture" \
  failed_with 'unsupported architecture "riscv64"'
checks_nothing_changed "architecture riscv64"

rm /etc/os-release
run_installer latest
restore_os_release
check "/etc/os-release missing: the install fails with a message saying that /etc/os-release is missing" \
  failed_with '/etc/os-release is missing'
checks_nothing_changed "/etc/os-release missing"

# Runs install.sh with version latest on an /etc/os-release that holds only ID=$1, then puts back the image's file.
run_installer_with_os_id() {
  rm /etc/os-release
  printf 'ID=%s\n' "$1" >/etc/os-release
  run_installer latest
  restore_os_release
}

run_installer_with_os_id alpine
check "ID=alpine: the install fails with a message saying that upstream's builds need the GNU C library" \
  failed_with 'need the GNU C library'
checks_nothing_changed "ID=alpine"

run_installer_with_os_id arch
check "ID=arch: the install fails with a message naming the distribution" failed_with 'unsupported distribution "arch"'
checks_nothing_changed "ID=arch"

run_installer_with_os_id fedora
check "ID=fedora, no dnf: the install fails with a message naming the distribution and the missing package manager" \
  failed_with 'distribution "fedora"' 'package manager dnf is missing'
checks_nothing_changed "ID=fedora, no dnf"

# /usr/local/bin/godot is still a directory holding only the file keep, unchanged.
directory_left_as_it_is() {
  if [[ ! -d "${TARGET}" || "$(ls -A "${TARGET}")" != keep || "$(cat "${TARGET}/keep")" != keep ]]; then
    printf '  %s is no longer a directory holding only keep:\n' "${TARGET}"
    ls -lA "${TARGET}"
    show_run
    return 1
  fi
}

rm "${TARGET}"
mkdir "${TARGET}"
echo keep >"${TARGET}/keep"
run_installer latest
check "a directory at /usr/local/bin/godot: the install fails with a message naming the path" \
  failed_with /usr/local/bin/godot
check "a directory at /usr/local/bin/godot: nothing is downloaded or installed" nothing_downloaded_or_installed
check "a directory at /usr/local/bin/godot: the install leaves it as it is" directory_left_as_it_is
check "a directory at /usr/local/bin/godot: no temporary directory or staged executable remains" no_install_residue
restore_real_godot

# The runs that pass the prerequisites find the font configuration library; the real apt-get reinstalls it.
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends libfontconfig1
linker_cache="$(ldconfig -p)"
if [[ "${linker_cache}" != *libfontconfig.so.1* ]]; then
  echo 'libfontconfig.so.1 is not known to the dynamic linker after reinstalling libfontconfig1' >&2
  exit 1
fi

# Checks that the last run, named $1, which failed, left /usr/local/bin/godot as it was and no residue.
checks_godot_kept() {
  check "$1: /usr/local/bin/godot is left as it was before the install" godot_unchanged
  check "$1: no temporary directory or staged executable remains" no_install_residue
}

run_installer 4.6.9
check "version 4.6.9 without a release: the install fails with a message naming the version" failed_with 4.6.9
checks_godot_kept "version 4.6.9 without a release"

# 4.2.2, the minimum itself, passes the version checks: the run goes on to request release 4.2.2-stable, which no
# fixture holds.
run_installer 4.2.2
check "version 4.2.2, the minimum: the install requests the release's checksum list" \
  failed_with 'releases/download/4.2.2-stable/SHA512-SUMS.txt'
checks_godot_kept "version 4.2.2, the minimum"

for tag in 4.7.0-stable 3.6.3-stable 4.2.1-stable; do
  printf '%s\n' "${tag}" >"${FIXTURE_DIR}/latest"
  run_installer latest
  check "latest pointing to ${tag}: the install fails with a message naming the tag" failed_with "\"${tag}\""
  check "latest pointing to ${tag}: no archive is downloaded" requested_only_latest
  checks_godot_kept "latest pointing to ${tag}"
done

archive="Godot_v4.6.1-stable_linux.${ARCH}.zip"

make_release 4.6.1
echo checksum_list_404 >"${FIXTURE_DIR}/mode"
run_installer 4.6.1
check "a missing checksum list: the install fails with a message naming the checksum list" \
  failed_with SHA512-SUMS.txt
checks_godot_kept "a missing checksum list"

echo archive_404 >"${FIXTURE_DIR}/mode"
run_installer 4.6.1
check "a release without an archive for ${ARCH}: the install fails with a message naming the archive" \
  failed_with "${archive}"
checks_godot_kept "a release without an archive for ${ARCH}"
echo serve >"${FIXTURE_DIR}/mode"

make_release 4.6.1 missing_entry
run_installer 4.6.1
check "no entry for the archive: the install fails with a message naming the archive and saying verification failed" \
  failed_with "${archive}" 'verification failed'
checks_godot_kept "no entry for the archive"

make_release 4.6.1 duplicate_entry
run_installer 4.6.1
check "two archive entries: the install fails with a message naming the archive and saying verification failed" \
  failed_with "${archive}" 'verification failed'
checks_godot_kept "two archive entries"

make_release 4.6.1 digest_mismatch
run_installer 4.6.1
check "a digest mismatch: the install fails with a message saying verification failed" failed_with 'verification failed'
checks_godot_kept "a digest mismatch"

make_release 4.6.1 extra_entry
run_installer 4.6.1
check "an archive with an extra entry: the install fails with a message naming the archive" failed_with "${archive}"
checks_godot_kept "an archive with an extra entry"

make_release 4.6.1 renamed_entry
run_installer 4.6.1
check "an archive whose only entry has another name: the install fails with a message naming the archive" \
  failed_with "${archive}"
checks_godot_kept "an archive whose only entry has another name"

make_release 4.6.1 exits_nonzero
run_installer 4.6.1
check "an executable that exits non-zero: the install fails with a message naming the version check" \
  failed_with 'the version check'
checks_godot_kept "an executable that exits non-zero"

make_release 4.6.1 other_version
run_installer 4.6.1
check "an executable that reports another version: the install fails with a message naming the version check" \
  failed_with 'the version check'
checks_godot_kept "an executable that reports another version"

# /usr/local/bin/godot is the executable from this machine's archive of fixture release $1-stable.
target_is_release_executable() {
  local tag="$1-stable"
  local expected
  local actual
  expected="$(unzip -p "${FIXTURE_DIR}/releases/${tag}/Godot_v${tag}_linux.${ARCH}.zip" \
    "Godot_v${tag}_linux.${ARCH}" | sha512sum)"
  actual="$(sha512sum <"${TARGET}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '  %s is not the executable of release %s:\n' "${TARGET}" "${tag}"
    cat "${TARGET}"
    show_run
    return 1
  fi
}

# godot --version exits 0 and prints exactly $1.
godot_reports() {
  local output
  if ! output="$(godot --version)" || [[ "${output}" != "$1" ]]; then
    printf '  godot --version printed "%s", expected "%s"\n' "${output}" "$1"
    show_run
    return 1
  fi
}

make_release 4.6
# It prints the line of an official 4.6 build but exits 1, so only its exit status makes the version unreadable.
printf '#!/bin/sh\necho 4.6.stable.official.0123456789\nexit 1\n' >"${TARGET}"
run_installer 4.6
check "an installed godot that exits 1: the install succeeds" succeeded
check "an installed godot that exits 1: the install replaces it" target_is_release_executable 4.6
check "an installed godot that exits 1: godot --version reports the requested version" \
  godot_reports 4.6.stable.official.0123456789
check "an installed godot that exits 1: no temporary directory or staged executable remains" no_install_residue

printf '#!/bin/sh\necho 4.6.stable.custom_build.0123456789\n' >"${TARGET}"
run_installer 4.6
check "an installed godot that reports a custom build: the install succeeds" succeeded
check "an installed godot that reports a custom build: the install replaces it" target_is_release_executable 4.6
check "an installed godot that reports a custom build: godot --version reports the requested version" \
  godot_reports 4.6.stable.official.0123456789
check "an installed godot that reports a custom build: no temporary directory or staged executable remains" \
  no_install_residue

reportResults
