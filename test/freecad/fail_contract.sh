#!/usr/bin/env bash
# Runs the installer against local release fixtures to check version validation, release resolution, asset selection,
# transport and checksum failures, platform rejection, conflicts, repeat installation, and recovery. The real
# installation from the build is checked first, moved aside, and restored at the end.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
test_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${test_dir}/helpers.sh"

readonly API_PREFIX="https://api.github.com/repos/FreeCAD/FreeCAD/releases"
readonly DOWNLOAD_PREFIX="https://github.com/FreeCAD/FreeCAD/releases/download"
ARCH="$(uname -m)"
readonly ARCH

check "no Python interpreter is installed beside FreeCAD's own" bash -c '! command -v python3 && ! command -v python'
check "no display server is installed" bash -c '! command -v Xorg && ! command -v Xvfb && ! command -v Xvnc'

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR
mv "${TREE}" "${FIXTURE_DIR}/original"
rm /usr/local/bin/freecad /usr/local/bin/freecadcmd
restore() {
  rm -rf "${TREE}" /usr/local/bin/freecad /usr/local/bin/freecadcmd
  mv "${FIXTURE_DIR}/original" "${TREE}"
  ln -s "${TREE}/bin/freecad" /usr/local/bin/freecad
  ln -s "${TREE}/bin/freecadcmd" /usr/local/bin/freecadcmd
  rm -rf "${FIXTURE_DIR}"
}
trap restore EXIT
mkdir -p "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/api/tags" "${FIXTURE_DIR}/releases"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
chmod +x "${FIXTURE_DIR}/bin/curl"
printf 'normal\n' >"${FIXTURE_DIR}/mode"
touch "${FIXTURE_DIR}/requests"

# Prints the name of the stand-in AppImage of release $1; $2 replaces the `-py311` part of the name.
asset_name() {
  printf 'FreeCAD_%s-Linux-%s%s.AppImage\n' "$1" "${ARCH}" "${2--py311}"
}

# Writes the API metadata of release $1 to file $2, with prerelease $3, draft $4, and the remaining arguments as its
# asset names.
write_metadata() {
  local release="$1"
  local file="$2"
  local prerelease="$3"
  local draft="$4"
  local name
  local separator=""
  shift 4
  {
    printf '{"tag_name": "%s", "draft": %s, "prerelease": %s, "assets": [' "${release}" "${draft}" "${prerelease}"
    for name in "$@"; do
      printf '%s{"name": "%s"}' "${separator}" "${name}"
      separator=", "
    done
    printf ']}\n'
  } >"${file}"
}

# Builds a stand-in AppImage whose freecadcmd reports release $1, with its checksum file and its API metadata; $2 is
# normal, incompatible (freecadcmd fails), or active_failure (it fails only when run from /opt/freecad); $3 replaces
# the `-py311` part of the asset name. The stand-in unpacks its payload on --appimage-extract, as an AppImage does.
make_release() {
  local release="$1"
  local behavior="${2-normal}"
  local dir="${FIXTURE_DIR}/releases/${release}"
  local name
  local program
  name="$(asset_name "${release}" "${3--py311}")"
  rm -rf "${dir}"
  mkdir -p "${dir}/payload/usr/bin" "${dir}/payload/usr/ssl"
  for program in freecad freecadcmd; do
    cat >"${dir}/payload/usr/bin/${program}" <<SCRIPT
#!/usr/bin/env bash
if [[ '${behavior}' == incompatible ]]; then exit 1; fi
if [[ '${behavior}' == active_failure && "\$0" == /opt/freecad/usr/bin/* ]]; then exit 1; fi
printf 'FreeCAD %s Revision: fixture\\n' '${release}'
SCRIPT
  done
  printf '#!/bin/sh\nexit 0\n' >"${dir}/payload/usr/bin/python"
  printf 'fixture certificates\n' >"${dir}/payload/usr/ssl/cacert.pem"
  chmod +x "${dir}/payload/usr/bin/"*
  # Upstream's build leaves some files group-writable; the installer must not keep that.
  chmod 0664 "${dir}/payload/usr/ssl/cacert.pem"
  cat >"${dir}/${name}" <<SCRIPT
#!/usr/bin/env bash
# Stand-in for the AppImage of FreeCAD ${release}.
[[ "\${1-}" == --appimage-extract ]] || exit 64
touch '${dir}/executed'
cp -a '${dir}/payload' squashfs-root
find squashfs-root -type f
SCRIPT
  printf '%s  %s\n' "$(sha256sum "${dir}/${name}" | cut -d ' ' -f 1)" "${name}" >"${dir}/${name}-SHA256.txt"
  write_metadata "${release}" "${FIXTURE_DIR}/api/tags/${release}.json" false false \
    "freecad_source_${release}.tar.gz" "FreeCAD_${release}-Linux-other-py311.AppImage" "${name}" \
    "${name}-SHA256.txt" "${name}.zsync" "FreeCAD_${release}-Windows-x86_64-py311.7z"
}

# Writes page $1 of the release listing, holding one release per remaining argument, written as tag, tag:prerelease,
# or tag:draft.
make_listing_page() {
  local page="$1"
  local entry
  local separator=""
  shift
  {
    printf '['
    for entry in "$@"; do
      printf '%s{"tag_name": "%s", "draft": %s, "prerelease": %s, "assets": []}' "${separator}" "${entry%%:*}" \
        "$([[ "${entry}" == *:draft ]] && echo true || echo false)" \
        "$([[ "${entry}" == *:prerelease ]] && echo true || echo false)"
      separator=", "
    done
    printf ']\n'
  } >"${FIXTURE_DIR}/api/page${page}.json"
}

# Succeeds when the installer fails for VERSION $1, with _REMOTE_USER $3 when given, printing a message matching $2.
fails_with() {
  if run_installer "$1" "${3-}"; then
    printf 'the installer accepted version "%s"\n' "$1" >&2
    return 1
  fi
  grep -q -- "$2" "${FIXTURE_DIR}/output"
}

# Succeeds when the installer fails for VERSION $1 with a message matching $2 and FreeCAD still reports release $3.
failed_and_kept() {
  fails_with "$1" "$2" && reports_release "$3"
}

# Prints the number of requests the fixture has answered so far.
requests() {
  wc -l <"${FIXTURE_DIR}/requests"
}

# Succeeds when no request since request number $1 asked for an AppImage.
no_appimage_requested_since() {
  ! tail -n "+$(($1 + 1))" "${FIXTURE_DIR}/requests" | grep -q 'AppImage$'
}

# Makes every package look missing and records package installations, so a run that installs packages shows it.
stub_package_manager() {
  printf '#!/bin/sh\nexit 1\n' >"${FIXTURE_DIR}/bin/dpkg-query"
  cat >"${FIXTURE_DIR}/bin/apt-get" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"${FIXTURE_DIR}/apt-get"
STUB
  chmod +x "${FIXTURE_DIR}/bin/dpkg-query" "${FIXTURE_DIR}/bin/apt-get"
}

make_release 1.1.2
make_release 1.1.9
make_release 1.1.10
make_release 1.2.0
make_release 1.2.1 normal -py313
make_release 1.3.0 normal ""
cp "${FIXTURE_DIR}/api/tags/1.2.0.json" "${FIXTURE_DIR}/api/latest.json"
# A listing in no useful order, with weekly builds, a pre-release and a draft with plain tags, and an older series.
make_listing_page 1 weekly-2026.11.25:prerelease 1.1.9 1.1.12:draft 1.2.0 1.1.11:prerelease 1.1.10 1.0.2 1.1.2 \
  weekly-2026.11.18:prerelease

before="$(requests)"
stub_package_manager
for value in '' latest- v1.1.4 1.1.4-rc1 weekly-2026.11.25 1.1.4.1 1 01.1 1.0 1.0.2 0.21.2 garbage; do
  check "version \"${value}\" fails naming the accepted forms" \
    fails_with "${value}" "option version is \"${value}\".*use latest, a series"
done
check "invalid versions fail before any request" test "$(requests)" = "${before}"
check "invalid versions fail before installing packages" test ! -e "${FIXTURE_DIR}/apt-get"
rm "${FIXTURE_DIR}/bin/dpkg-query" "${FIXTURE_DIR}/bin/apt-get"

previous_umask="$(umask)"
umask 077
check "an exact release installs" run_installer 1.1.2
umask "${previous_umask}"
check "the exact release is active" reports_release 1.1.2
check "a non-root user runs FreeCAD installed under a restrictive umask" \
  runuser --user nobody -- /usr/local/bin/freecadcmd --version
check "the installation belongs to root and only root can write it" tree_is_root_only
check "freecad and freecadcmd link to the launchers" links_target_launchers
check "an exact release reads only its own metadata" \
  test "$(grep -c "^${API_PREFIX}" "${FIXTURE_DIR}/requests")" = 1

check "a series selects its numerically highest stable release" run_installer 1.1
check "the series release is 1.1.10, not 1.1.9 or a pre-release" reports_release 1.1.10
check "latest selects the release GitHub reports as latest" run_installer latest
check "latest selects 1.2.0" reports_release 1.2.0
check "an asset name with another Python version is accepted" run_installer 1.2.1
check "the release with another Python version is active" reports_release 1.2.1
check "an asset name without a Python version is accepted" run_installer 1.3.0
check "the release without a Python version is active" reports_release 1.3.0
check "release 1.2.0 installs again" run_installer 1.2.0

check "a series without a stable release fails naming it and keeps the installation" \
  failed_and_kept 1.4 'holds no stable release of the series 1.4' 1.2.0
check "a release that does not exist fails naming its metadata URL" \
  failed_and_kept 1.1.99 "cannot read the release metadata ${API_PREFIX}/tags/1.1.99" 1.2.0
write_metadata 1.5.0 "${FIXTURE_DIR}/api/tags/1.5.0.json" true false "$(asset_name 1.5.0)"
check "an exact release that is a pre-release fails" failed_and_kept 1.5.0 'is a draft or a pre-release' 1.2.0
write_metadata 1.5.0 "${FIXTURE_DIR}/api/tags/1.5.0.json" false true "$(asset_name 1.5.0)"
check "an exact release that is a draft fails" failed_and_kept 1.5.0 'is a draft or a pre-release' 1.2.0

cp "${FIXTURE_DIR}/api/latest.json" "${FIXTURE_DIR}/latest.saved"
write_metadata weekly-2026.11.25 "${FIXTURE_DIR}/api/latest.json" false false FreeCAD_weekly.AppImage
check "a latest release whose tag is not a plain version fails naming the tag" \
  failed_and_kept latest 'names the release "weekly-2026.11.25", whose tag is not a plain version' 1.2.0
write_metadata 1.6.0 "${FIXTURE_DIR}/api/latest.json" true false "$(asset_name 1.6.0)"
check "a latest release that is a pre-release fails naming the tag" \
  failed_and_kept latest 'names the release 1.6.0, which is a draft or a pre-release' 1.2.0
write_metadata 1.0.2 "${FIXTURE_DIR}/api/latest.json" false false FreeCAD_1.0.2-conda-Linux-x86_64-py311.AppImage
check "a latest release older than 1.1.0 fails naming the tag" \
  failed_and_kept latest 'names the release 1.0.2, older than 1.1.0' 1.2.0
printf 'not json\n' >"${FIXTURE_DIR}/api/latest.json"
check "unreadable metadata fails naming its URL" failed_and_kept latest "${API_PREFIX}/latest is not a JSON" 1.2.0
cp "${FIXTURE_DIR}/api/page1.json" "${FIXTURE_DIR}/page1.saved"
printf '{"message": "not a list"}\n' >"${FIXTURE_DIR}/api/page1.json"
check "a listing that is not a list fails naming its URL" \
  failed_and_kept 1.1 "${API_PREFIX}?per_page=100&page=1 is not a JSON list" 1.2.0
mv "${FIXTURE_DIR}/page1.saved" "${FIXTURE_DIR}/api/page1.json"
mv "${FIXTURE_DIR}/latest.saved" "${FIXTURE_DIR}/api/latest.json"

before="$(requests)"
write_metadata 1.7.0 "${FIXTURE_DIR}/api/tags/1.7.0.json" false false "FreeCAD_1.7.0-Linux-other-py311.AppImage" \
  "$(asset_name 1.7.0)-SHA256.txt" "$(asset_name 1.7.0).zsync"
check "a release without an AppImage for the architecture fails naming it" \
  failed_and_kept 1.7.0 "release 1.7.0 holds 0 AppImages for ${ARCH}" 1.2.0
write_metadata 1.7.0 "${FIXTURE_DIR}/api/tags/1.7.0.json" false false "$(asset_name 1.7.0)" \
  "$(asset_name 1.7.0 -py313)" "$(asset_name 1.7.0)-SHA256.txt"
check "a release with two AppImages for the architecture fails naming it" \
  failed_and_kept 1.7.0 "release 1.7.0 holds 2 AppImages for ${ARCH}" 1.2.0
write_metadata 1.7.0 "${FIXTURE_DIR}/api/tags/1.7.0.json" false false "$(asset_name 1.7.0)"
check "a release without a checksum file fails naming it" \
  failed_and_kept 1.7.0 "holds no checksum file $(asset_name 1.7.0)-SHA256.txt" 1.2.0
check "no AppImage is requested when the asset or its checksum file is missing" no_appimage_requested_since "${before}"

for mode in network:'cannot read the release listing' rate_limit:'cannot read the release listing .*rate limit' \
  missing_checksum:"cannot download .*$(asset_name 1.1.10)-SHA256.txt" missing_entry:'holds 0 entries' \
  duplicate:'holds 2 entries' corrupt:"$(asset_name 1.1.10) does not match"; do
  printf '%s\n' "${mode%%:*}" >"${FIXTURE_DIR}/mode"
  rm -f "${FIXTURE_DIR}/releases/1.1.10/executed"
  check "a ${mode%%:*} failure stops the installation and keeps the previous release" \
    failed_and_kept 1.1 "${mode#*:}" 1.2.0
  check "nothing from the AppImage ran after the ${mode%%:*} failure" \
    test ! -e "${FIXTURE_DIR}/releases/1.1.10/executed"
done
printf 'rate_limit\n' >"${FIXTURE_DIR}/mode"
check "a rate-limit response for an exact release fails naming the URL" \
  failed_and_kept 1.1.10 "cannot read the release metadata ${API_PREFIX}/tags/1.1.10" 1.2.0
printf 'normal\n' >"${FIXTURE_DIR}/mode"
check "no staging directory is left in /opt after failures" bash -c '! compgen -G "/opt/.freecad-feature.*"'

make_release 1.1.10 incompatible
check "a release that cannot run fails naming it and keeps the previous release" \
  failed_and_kept 1.1.10 'FreeCAD 1.1.10 cannot run on this image' 1.2.0
make_release 1.1.10 active_failure
check "a failed activation restores the previous release" \
  failed_and_kept 1.1.10 'activated FreeCAD 1.1.10 does not report' 1.2.0
check "a failed activation restores the links" links_target_launchers
make_release 1.1.10

check "a downgrade succeeds" run_installer 1.1.2
check "the downgrade is active" reports_release 1.1.2
check "an upgrade succeeds" run_installer 1.1.10
check "the upgrade is active" reports_release 1.1.10
check "no staging directory is left in /opt" bash -c '! compgen -G "/opt/.freecad-feature.*"'
check "the downloaded AppImage is not kept" bash -c '! find /opt -name "*.AppImage" | grep -q .'

touch "${TREE}/sentinel"
before="$(requests)"
check "the installed release installs again" run_installer 1.1.10
check "a healthy installation of the same release is kept" test -f "${TREE}/sentinel"
check "the same release is not downloaded again" no_appimage_requested_since "${before}"
check "a series is resolved anew and keeps the matching installation" run_installer 1.1
check "the series kept the installation" test -f "${TREE}/sentinel"
check "latest is resolved anew" run_installer latest
check "latest replaces the installation with 1.2.0" reports_release 1.2.0

printf '#!/bin/sh\nexit 1\n' >"${TREE}/usr/bin/freecadcmd"
printf 'corrupt\n' >"${FIXTURE_DIR}/mode"
check "a failed repair reports the failure" fails_with 1.2.0 'does not match'
check "a failed repair keeps the unhealthy tree" grep -q 'exit 1' "${TREE}/usr/bin/freecadcmd"
printf 'normal\n' >"${FIXTURE_DIR}/mode"
check "an unhealthy installation of the same release is repaired" run_installer 1.2.0
check "the repaired release runs" reports_release 1.2.0

for name in freecad freecadcmd; do
  mv "/usr/local/bin/${name}" "${FIXTURE_DIR}/link"
  cat >"/usr/local/bin/${name}" <<'FOREIGN'
#!/bin/sh
# A foreign installation reporting the requested release.
touch "${FIXTURE_DIR}/foreign_executed"
printf 'FreeCAD 1.2.0 Revision: foreign\n'
FOREIGN
  chmod +x "/usr/local/bin/${name}"
  check "a foreign ${name} at the command path fails the installation" \
    fails_with 1.2.0 "/usr/local/bin/${name} is occupied"
  check "the foreign ${name} is kept" grep -q foreign "/usr/local/bin/${name}"
  check "the foreign ${name} is never executed" test ! -e "${FIXTURE_DIR}/foreign_executed"
  rm "/usr/local/bin/${name}"
  ln -s /does/not/exist "/usr/local/bin/${name}"
  check "a broken link at the ${name} command path fails the installation" \
    fails_with 1.2.0 "/usr/local/bin/${name} is occupied"
  check "the broken ${name} link is kept" test "$(readlink "/usr/local/bin/${name}")" = /does/not/exist
  rm "/usr/local/bin/${name}"
  mv "${FIXTURE_DIR}/link" "/usr/local/bin/${name}"
  printf '#!/bin/sh\necho foreign\n' >"${FIXTURE_DIR}/bin/${name}"
  chmod +x "${FIXTURE_DIR}/bin/${name}"
  check "a foreign ${name} elsewhere on PATH fails the installation" \
    fails_with 1.2.0 "${FIXTURE_DIR}/bin/${name} conflicts with this feature"
  rm "${FIXTURE_DIR}/bin/${name}"
done
mv "${MARKER}" "${FIXTURE_DIR}/marker"
check "a tree without the marker is unmanaged" fails_with 1.2.0 "${TREE} is unmanaged"
mv "${FIXTURE_DIR}/marker" "${MARKER}"
useradd --create-home freecad_probe
mkdir -p /home/freecad_probe/.local/bin
printf '#!/bin/sh\necho foreign\n' >/home/freecad_probe/.local/bin/freecadcmd
chmod +x /home/freecad_probe/.local/bin/freecadcmd
check "a foreign freecadcmd on the remote user's PATH fails the installation" \
  fails_with 1.2.0 '/home/freecad_probe/.local/bin/freecadcmd conflicts with this feature' freecad_probe
userdel --remove freecad_probe
check "the managed installation is still accepted" run_installer 1.2.0

before="$(requests)"
stub_package_manager
cp -L /etc/os-release "${FIXTURE_DIR}/os-release"
printf 'ID=alpine\n' >/etc/os-release
check "an unsupported distribution is identified" fails_with 1.2.0 'unsupported distribution "alpine"'
cat "${FIXTURE_DIR}/os-release" >/etc/os-release
ln -s /does/not/exist "/lib/ld-musl-${ARCH}.so.1"
printf '#!/bin/sh\nexit 1\n' >"${FIXTURE_DIR}/bin/getconf"
chmod +x "${FIXTURE_DIR}/bin/getconf"
check "a musl-based image is rejected" fails_with 1.2.0 '"debian" is musl-based, which is unsupported'
rm "${FIXTURE_DIR}/bin/getconf"
printf '#!/bin/sh\necho riscv64\n' >"${FIXTURE_DIR}/bin/uname"
chmod +x "${FIXTURE_DIR}/bin/uname"
check "an architecture other than amd64 and arm64 fails naming it" \
  fails_with 1.2.0 'unsupported architecture riscv64'
rm "${FIXTURE_DIR}/bin/uname"
# A 32-bit image on a 64-bit kernel: uname still reports the kernel's architecture, the package manager the image's.
printf '#!/bin/sh\necho i386\n' >"${FIXTURE_DIR}/bin/dpkg"
chmod +x "${FIXTURE_DIR}/bin/dpkg"
check "an i386 image on a 64-bit kernel fails naming its architecture" \
  fails_with 1.2.0 'unsupported architecture i386'
rm "${FIXTURE_DIR}/bin/dpkg"
check "unsupported platforms fail before any request" test "$(requests)" = "${before}"
check "unsupported platforms fail before installing packages" test ! -e "${FIXTURE_DIR}/apt-get"
rm "${FIXTURE_DIR}/bin/dpkg-query" "${FIXTURE_DIR}/bin/apt-get"
check "a glibc image with a musl loader installs" run_installer 1.2.0
rm "/lib/ld-musl-${ARCH}.so.1"

check "every request went to the FreeCAD project's GitHub releases" \
  bash -c "! grep -v -e '^${API_PREFIX}' -e '^${DOWNLOAD_PREFIX}/' '${FIXTURE_DIR}/requests'"
check "every request is HTTPS-only, redirects included" \
  bash -c "! grep -v -e '--proto =https --proto-redir =https' '${FIXTURE_DIR}/arguments'"

reportResults
