#!/usr/bin/env bash
# Scenario fail_installation: godot-dotnet installed with version 4.6 on debian:12, run as root. The script runs
# install.sh itself through installer.sh, with fixture_curl.sh serving fixture releases it builds, and checks what a
# successful image build cannot show: a matching installed version is skipped without a request; every failing run
# leaves the installation as it was and no residue, and a run that must fail before any change requests, installs, and
# changes nothing; the paths the feature does not own are refused; an installation whose version cannot be read, or
# whose link or install root is missing, is replaced by a new release directory.
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
# What the fixture executable of release 4.6-stable prints for --version.
readonly FIXTURE_LINE="4.6.stable.mono.official.0123456789"

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR

# zip and zipnote build the fixture archives. The real apt-get installs them before any stub is on PATH, and the
# package lists stay for reinstalling libfontconfig1 below.
DEBIAN_FRONTEND=noninteractive apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends zip

cp -P /etc/os-release "${FIXTURE_DIR}/os-release"

# Puts back the image's /etc/os-release, a symbolic link on debian:12.
restore_os_release() {
  rm -f /etc/os-release
  cp -P "${FIXTURE_DIR}/os-release" /etc/os-release
}

# Puts back /usr/bin/apt-get when a run set it aside.
restore_apt_get() {
  if [[ -e "${FIXTURE_DIR}/apt-get.real" ]]; then mv "${FIXTURE_DIR}/apt-get.real" /usr/bin/apt-get; fi
}

# Puts back what the script changes outside the fixture directory and the installation, and removes that directory,
# on every exit.
cleanup() {
  restore_os_release
  restore_apt_get
  rm -rf "${FIXTURE_DIR}"
}
trap cleanup EXIT

mkdir "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/bin-without-apt-get" "${FIXTURE_DIR}/riscv64"
cp "$(dirname "$0")/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
cp "$(dirname "$0")/fixture_curl.sh" "${FIXTURE_DIR}/bin-without-apt-get/curl"
cat >"${FIXTURE_DIR}/bin/apt-get" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${FIXTURE_DIR}/apt-get.calls"
exit 1
STUB
# install.sh reads the machine architecture from uname -m.
printf '#!/bin/sh\necho riscv64\n' >"${FIXTURE_DIR}/riscv64/uname"
chmod 0755 "${FIXTURE_DIR}/bin/curl" "${FIXTURE_DIR}/bin-without-apt-get/curl" "${FIXTURE_DIR}/bin/apt-get" \
  "${FIXTURE_DIR}/riscv64/uname"
echo serve >"${FIXTURE_DIR}/mode"

# Builds release $1-stable under ${FIXTURE_DIR}/releases, replacing an earlier build: for x86_64 and arm64, an archive
# Godot_v<tag>_mono_linux_<arch>.zip holding the top directory Godot_v<tag>_mono_linux_<arch>/ with the executable
# Godot_v<tag>_mono_linux.<arch>, a shell script that prints "$1.stable.mono.official.0123456789" for --version, and
# GodotSharp/Api/Release/GodotPlugins.dll; and SHA512-SUMS.txt with one entry per archive in sha512sum format. $2 names
# one defect: exits_nonzero (the executable prints that line but exits 1), other_version (it reports 4.6.2),
# standard_build (it reports the standard build), missing_entry and duplicate_entry (the list holds no entry or two for
# this machine's archive), digest_mismatch (the archives differ from their entries), outside_entry (README.txt beside
# the top directory), extra_entry (README.txt in it), symlink_entry (a link in GodotSharp/), vms_symlink_entry (a link
# in GodotSharp/ whose entry is marked as made on VMS, so the listing shows no Unix mode for it), dotdot_entry (an
# entry named <top>/GodotSharp/../../evil), no_executable, no_godotsharp, and godotsharp_file (GodotSharp is a file).
make_release() {
  local version="$1"
  local defect="${2-none}"
  local tag="${version}-stable"
  local release="${FIXTURE_DIR}/releases/${tag}"
  local build="${FIXTURE_DIR}/build"
  local reported="${version}.stable.mono.official.0123456789"
  local exit_status=0
  local arch
  local top
  local executable
  local archive
  local entries
  local offset
  case "${defect}" in
    exits_nonzero) exit_status=1 ;;
    other_version) reported="4.6.2.stable.mono.official.0123456789" ;;
    standard_build) reported="${version}.stable.official.0123456789" ;;
  esac
  rm -rf "${release}"
  mkdir -p "${release}"
  for arch in x86_64 arm64; do
    top="Godot_v${tag}_mono_linux_${arch}"
    executable="Godot_v${tag}_mono_linux.${arch}"
    archive="${top}.zip"
    rm -rf "${build}"
    mkdir -p "${build}/${top}/GodotSharp/Api/Release"
    echo 'fixture assembly' >"${build}/${top}/GodotSharp/Api/Release/GodotPlugins.dll"
    cat >"${build}/${top}/${executable}" <<EXECUTABLE
#!/bin/sh
# Fixture of the executable of Godot release ${tag} (.NET): answers --version only.
if [ "\$1" != --version ]; then exit 2; fi
echo ${reported}
exit ${exit_status}
EXECUTABLE
    chmod 0755 "${build}/${top}/${executable}"
    entries=("${top}")
    case "${defect}" in
      outside_entry)
        echo 'not part of a release' >"${build}/README.txt"
        entries+=(README.txt)
        ;;
      extra_entry) echo 'not part of a release' >"${build}/${top}/README.txt" ;;
      symlink_entry) ln -s /etc/passwd "${build}/${top}/GodotSharp/link" ;;
      vms_symlink_entry)
        ln -s /root "${build}/${top}/GodotSharp/link"
        # Added first, so its record is the first in the central directory.
        (cd "${build}" && zip -q --symlinks "${release}/${archive}" "${top}/GodotSharp/link")
        ;;
      dotdot_entry) echo 'not part of a release' >"${build}/${top}/GodotSharp/evil" ;;
      no_executable) rm "${build}/${top}/${executable}" ;;
      no_godotsharp) rm -r "${build}/${top}/GodotSharp" ;;
      godotsharp_file)
        rm -r "${build}/${top}/GodotSharp"
        echo 'not a directory' >"${build}/${top}/GodotSharp"
        ;;
    esac
    # --symlinks stores a link as a link instead of following it.
    (cd "${build}" && zip -q -r --symlinks "${release}/${archive}" "${entries[@]}")
    if [[ "${defect}" == vms_symlink_entry ]]; then
      # Byte 5 of a central directory record is the host system the entry was made on; 2 is VMS.
      offset="$(grep -obUaP '\x50\x4b\x01\x02' "${release}/${archive}" | head -n 1 | cut -d: -f1)"
      printf '\x02' | dd of="${release}/${archive}" bs=1 seek=$(( offset + 5 )) count=1 conv=notrunc status=none
    fi
    if [[ "${defect}" == dotdot_entry ]]; then
      # zipnote renames an entry: the line after "@ <name>" gives the new name as "@=<name>".
      zipnote "${release}/${archive}" \
        | sed "s|^@ ${top}/GodotSharp/evil\$|&\n@=${top}/GodotSharp/../../evil|" >"${FIXTURE_DIR}/notes"
      zipnote -w "${release}/${archive}" <"${FIXTURE_DIR}/notes"
    fi
    if [[ "${defect}" == missing_entry && "${arch}" == "${ARCH}" ]]; then continue; fi
    (cd "${release}" && sha512sum "${archive}") >>"${release}/SHA512-SUMS.txt"
    if [[ "${defect}" == duplicate_entry && "${arch}" == "${ARCH}" ]]; then
      (cd "${release}" && sha512sum "${archive}") >>"${release}/SHA512-SUMS.txt"
    fi
    if [[ "${defect}" == digest_mismatch ]]; then echo tampered >>"${release}/${archive}"; fi
  done
}

# Version 4.6, given in each form that selects it, matches the installation the CLI made.
state="$(installation_state)"
for value in 4.6 4.6.0 4.6-stable; do
  run_installer "${value}"
  check "version ${value} with 4.6 installed: the install succeeds" succeeded
  check "version ${value} with 4.6 installed: /opt/godot-dotnet and /usr/local/bin/godot are left unchanged" \
    installation_is "${state}"
  check "version ${value} with 4.6 installed: no archive is downloaded, and nothing else is requested" \
    requested_nothing
  check "version ${value} with 4.6 installed: no install residue remains" no_install_residue
done

# The runs that must fail before any change find the font configuration library missing, as a fresh debian:12 does,
# so a run that reached the prerequisites would call the apt-get stub.
dpkg --remove libfontconfig1
linker_cache="$(ldconfig -p)"
if [[ "${linker_cache}" == *libfontconfig.so.1* ]]; then
  echo 'libfontconfig.so.1 is still known to the dynamic linker after removing libfontconfig1' >&2
  exit 1
fi

# Checks that the last run, named $1, which failed before any change, requested, installed, and left behind nothing,
# and left the installation as installation_state printed it in $2.
checks_nothing_changed() {
  check "$1: nothing is downloaded or installed" nothing_downloaded_or_installed
  check "$1: /opt/godot-dotnet and /usr/local/bin/godot are left as they were" installation_is "$2"
  check "$1: no temporary directory or temporary link remains" no_temp_residue
}

state="$(installation_state)"
for value in 4 v4.7.2 4.7.2.1 4.06 master; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message naming the accepted forms" \
    failed_with 'use "latest" or a stable release MAJOR.MINOR or MAJOR.MINOR.PATCH'
  checks_nothing_changed "version ${value}" "${state}"
done

for value in 4.8-beta2 4.7-rc1; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message saying that only stable releases are accepted" \
    failed_with 'only stable releases are accepted'
  checks_nothing_changed "version ${value}" "${state}"
done

for value in 4.1.4 4.2 4.2.1; do
  run_installer "${value}"
  check "version ${value}: the install fails with a message naming 4.2.2 as the minimum" failed_with 'the minimum 4.2.2'
  checks_nothing_changed "version ${value}" "${state}"
done

run_installer latest "${FIXTURE_DIR}/riscv64"
check "architecture riscv64: the install fails with a message naming the architecture" \
  failed_with 'unsupported architecture "riscv64"'
checks_nothing_changed "architecture riscv64" "${state}"

rm /etc/os-release
run_installer latest
restore_os_release
check "/etc/os-release missing: the install fails with a message saying that /etc/os-release is missing" \
  failed_with '/etc/os-release is missing'
checks_nothing_changed "/etc/os-release missing" "${state}"

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
checks_nothing_changed "ID=alpine" "${state}"

for os_id in arch fedora; do
  run_installer_with_os_id "${os_id}"
  check "ID=${os_id}: the install fails with a message naming the distribution" \
    failed_with "unsupported distribution \"${os_id}\""
  checks_nothing_changed "ID=${os_id}" "${state}"
done

# debian:12 without apt-get: the real one is set aside, and the run's stubs hold curl alone.
mv /usr/bin/apt-get "${FIXTURE_DIR}/apt-get.real"
run_installer latest "" "${FIXTURE_DIR}/bin-without-apt-get"
restore_apt_get
check "no apt-get: the install fails with a message naming the distribution and the missing package manager" \
  failed_with 'distribution "debian"' 'package manager apt-get is missing'
checks_nothing_changed "no apt-get" "${state}"

real_target="$(readlink "${LINK}")"
real_release="${real_target%/godot}"

# Puts back the link the CLI made, whatever a preparation left at /usr/local/bin/godot.
restore_link() {
  rm -rf "${LINK}"
  ln -s "${real_target}" "${LINK}"
}

# Runs install.sh with version latest on the paths as a preparation left them, and checks that the run, named $1,
# failed before any change with a message containing every further argument, and left both paths as they were.
checks_path_refused() {
  local name="$1"
  local prepared
  shift
  prepared="$(installation_state)"
  run_installer latest
  check "${name}: the install fails with a message naming the path" failed_with "$@"
  checks_nothing_changed "${name}" "${prepared}"
}

rm "${LINK}"
printf '#!/bin/sh\necho 4.6.stable.official.0123456789\n' >"${LINK}"
chmod 0755 "${LINK}"
checks_path_refused "a regular file at /usr/local/bin/godot, as the godot feature installs it" \
  '/usr/local/bin/godot is a regular file' 'godot feature' 'cannot be combined'
restore_link

rm "${LINK}"
mkdir "${LINK}"
echo keep >"${LINK}/keep"
checks_path_refused "a directory at /usr/local/bin/godot" /usr/local/bin/godot
restore_link

for target in /usr/bin/true /nonexistent/godot "../../..${real_target}" /opt/godot-dotnet/../godot; do
  ln -sfn "${target}" "${LINK}"
  checks_path_refused "a link at /usr/local/bin/godot to ${target}" \
    "/usr/local/bin/godot is a symbolic link to \"${target}\""
done
restore_link

mv "${MARKER}" "${FIXTURE_DIR}/marker.real"
checks_path_refused "/opt/godot-dotnet without the marker" '/opt/godot-dotnet exists but holds no root-owned'
mv "${FIXTURE_DIR}/marker.real" "${MARKER}"

chown 1000:1000 "${MARKER}"
checks_path_refused "/opt/godot-dotnet with a marker not owned by root" \
  '/opt/godot-dotnet exists but holds no root-owned'
chown root:root "${MARKER}"

# The runs that pass the prerequisites find the font configuration library; the real apt-get reinstalls it.
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends libfontconfig1
linker_cache="$(ldconfig -p)"
if [[ "${linker_cache}" != *libfontconfig.so.1* ]]; then
  echo 'libfontconfig.so.1 is not known to the dynamic linker after reinstalling libfontconfig1' >&2
  exit 1
fi

# Checks that the last run, named $1, which failed, left the installation as installation_state printed it in $2, and
# no residue.
checks_installation_kept() {
  check "$1: /opt/godot-dotnet and /usr/local/bin/godot are left as they were before the install" installation_is "$2"
  check "$1: no install residue remains" no_install_residue
}

state="$(installation_state)"
run_installer 4.6.9
check "version 4.6.9 without a release: the install fails with a message naming the version" failed_with 4.6.9
checks_installation_kept "version 4.6.9 without a release" "${state}"

# 4.2.2, the minimum itself, passes the version checks: the run goes on to request release 4.2.2-stable, which no
# fixture holds.
run_installer 4.2.2
check "version 4.2.2, the minimum: the install requests the release's checksum list" \
  failed_with 'releases/download/4.2.2-stable/SHA512-SUMS.txt'
checks_installation_kept "version 4.2.2, the minimum" "${state}"

for tag in 4.7.0-stable 3.6.3-stable 4.2.1-stable; do
  printf '%s\n' "${tag}" >"${FIXTURE_DIR}/latest"
  run_installer latest
  check "latest pointing to ${tag}: the install fails with a message naming the tag" failed_with "\"${tag}\""
  check "latest pointing to ${tag}: no archive is downloaded" requested_only_latest
  checks_installation_kept "latest pointing to ${tag}" "${state}"
done

archive="Godot_v4.6.1-stable_mono_linux_${ARCH}.zip"

make_release 4.6.1
echo checksum_list_404 >"${FIXTURE_DIR}/mode"
run_installer 4.6.1
check "a missing checksum list: the install fails with a message naming the checksum list" \
  failed_with SHA512-SUMS.txt
checks_installation_kept "a missing checksum list" "${state}"

echo archive_404 >"${FIXTURE_DIR}/mode"
run_installer 4.6.1
check "a release without an archive for ${ARCH}: the install fails with a message naming the archive" \
  failed_with "${archive}"
checks_installation_kept "a release without an archive for ${ARCH}" "${state}"
echo serve >"${FIXTURE_DIR}/mode"

for defect in missing_entry duplicate_entry; do
  make_release 4.6.1 "${defect}"
  run_installer 4.6.1
  check "${defect}: the install fails with a message naming the archive and saying verification failed" \
    failed_with "${archive}" 'verification failed'
  checks_installation_kept "${defect}" "${state}"
done

make_release 4.6.1 digest_mismatch
run_installer 4.6.1
check "a digest mismatch: the install fails with a message saying verification failed" failed_with 'verification failed'
checks_installation_kept "a digest mismatch" "${state}"

for defect in outside_entry extra_entry symlink_entry vms_symlink_entry dotdot_entry no_executable no_godotsharp \
  godotsharp_file; do
  make_release 4.6.1 "${defect}"
  run_installer 4.6.1
  check "an archive with ${defect}: the install fails with a message naming the archive" failed_with "${archive}"
  checks_installation_kept "an archive with ${defect}" "${state}"
done

for defect in exits_nonzero other_version standard_build; do
  make_release 4.6.1 "${defect}"
  run_installer 4.6.1
  check "an executable with ${defect}: the install fails with a message naming the version check" \
    failed_with 'the version check'
  checks_installation_kept "an executable with ${defect}" "${state}"
done

make_release 4.6

# Checks that the last run, named $1, succeeded, switched the link away from release directory $2 to a new one for
# 4.6-stable, removed $2, and installed the fixture executable.
checks_switched() {
  check "$1: the install succeeds" succeeded
  check "$1: the link points into a new release directory, and the earlier one is removed" \
    switched_from "$2" 4.6-stable
  check "$1: godot --version reports the requested version" godot_reports "${FIXTURE_LINE}"
}

# It prints the line of an official 4.6 build but exits 1, so only its exit status makes the version unreadable.
printf '#!/bin/sh\necho 4.6.stable.mono.official.0123456789\nexit 1\n' >"${real_release}/godot"
run_installer 4.6
checks_switched "an installed godot that exits 1" "${real_release}"

current="$(dirname "$(readlink "${LINK}")")"
printf '#!/bin/sh\necho 4.6.stable.mono.custom_build.0123456789\n' >"${current}/godot"
run_installer 4.6
checks_switched "an installed godot that reports a custom build" "${current}"

current="$(dirname "$(readlink "${LINK}")")"
rm "${LINK}"
run_installer 4.6
checks_switched "/opt/godot-dotnet with the marker and no link" "${current}"

current="$(dirname "$(readlink "${LINK}")")"
ln -sfn /opt/godot-dotnet/missing.000000/godot "${LINK}"
run_installer 4.6
checks_switched "a link of the feature's form to a missing target" "${current}"

current="$(dirname "$(readlink "${LINK}")")"
rm -rf "${INSTALL_ROOT}"
run_installer 4.6
checks_switched "a link of the feature's form and no /opt/godot-dotnet" "${current}"

# The version check fails after /opt/godot-dotnet has been created for the first install, so the run must remove it.
rm -rf "${INSTALL_ROOT}" "${LINK}"
make_release 4.6.1 exits_nonzero
run_installer 4.6.1
check "a failed first install: the install fails at the version check" failed_with 'the version check'
check "a failed first install: neither /opt/godot-dotnet nor /usr/local/bin/godot exists afterwards" \
  installation_is "$(printf 'link absent\ninstall root absent')"
check "a failed first install: no temporary directory or temporary link remains" no_temp_residue

run_installer 4.6
check "a first install: the install succeeds" succeeded
check "a first install: godot --version reports the requested version" godot_reports "${FIXTURE_LINE}"
check "a first install: no install residue remains" no_install_residue

# /opt/godot-dotnet is made a link to the installation moved beside it, then a file; each is put back afterwards. The
# font configuration library is removed again, so a run that reached the prerequisites would call the apt-get stub.
dpkg --remove libfontconfig1
mv "${INSTALL_ROOT}" /opt/moved-godot-dotnet
ln -s /opt/moved-godot-dotnet "${INSTALL_ROOT}"
checks_path_refused "/opt/godot-dotnet as a link to a directory holding the marker" \
  '/opt/godot-dotnet exists but is not a directory this feature created'
rm "${INSTALL_ROOT}"

echo 'not a directory' >"${INSTALL_ROOT}"
checks_path_refused "/opt/godot-dotnet as a file" '/opt/godot-dotnet exists but is not a directory this feature created'
rm "${INSTALL_ROOT}"
mv /opt/moved-godot-dotnet "${INSTALL_ROOT}"

reportResults
