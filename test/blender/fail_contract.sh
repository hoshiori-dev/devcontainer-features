#!/usr/bin/env bash
# Runs the installer against local release fixtures to check version validation, release resolution, transport and
# checksum failures, platform rejection, conflicts, repeat installation, and recovery. The real installation from the
# build is checked first, moved aside, and restored at the end.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
test_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${test_dir}/helpers.sh"

check "no Python interpreter is installed beside Blender's own" bash -c '! command -v python3'

FIXTURE_DIR="$(mktemp -d)"
export FIXTURE_DIR
mv "${TREE}" "${FIXTURE_DIR}/original"
rm "${LINK}"
restore() {
  rm -rf "${TREE}" "${LINK}"
  mv "${FIXTURE_DIR}/original" "${TREE}"
  ln -s "${TREE}/blender" "${LINK}"
  rm -rf "${FIXTURE_DIR}"
}
trap restore EXIT
mkdir "${FIXTURE_DIR}/bin" "${FIXTURE_DIR}/listings" "${FIXTURE_DIR}/releases"
cp "${test_dir}/fixture_curl.sh" "${FIXTURE_DIR}/bin/curl"
chmod +x "${FIXTURE_DIR}/bin/curl"
printf 'normal\n' >"${FIXTURE_DIR}/mode"
touch "${FIXTURE_DIR}/requests"

# Builds a release archive whose blender reports release $1, with its checksum file; $2 is normal, incompatible (the
# executable fails), or active_failure (it fails only through /usr/local/bin/blender).
make_release() {
  local release="$1"
  local behavior="${2-normal}"
  local dir="${FIXTURE_DIR}/releases/${release}"
  local top="${dir}/blender-${release}-linux-x64"
  rm -rf "${dir}"
  mkdir -p "${top}/${release%.*}/python/bin"
  cat >"${top}/blender" <<SCRIPT
#!/usr/bin/env bash
if [[ '${behavior}' == incompatible ]]; then exit 1; fi
if [[ '${behavior}' == active_failure && "\$0" == /usr/local/bin/blender ]]; then exit 1; fi
printf 'Blender %s\\n\\tbuild hash: fixture\\n' '${release}'
SCRIPT
  printf '#!/bin/sh\nexit 0\n' >"${top}/${release%.*}/python/bin/python3.11"
  chmod +x "${top}/blender" "${top}/${release%.*}/python/bin/python3.11"
  tar -cJf "${dir}/blender-${release}-linux-x64.tar.xz" -C "${dir}" "blender-${release}-linux-x64"
  {
    printf '%s  blender-%s-windows-x64.zip\n' "$(printf windows | sha256sum | cut -d ' ' -f 1)" "${release}"
    printf '%s  blender-%s-linux-x64.tar.xz\n' \
      "$(sha256sum "${dir}/blender-${release}-linux-x64.tar.xz" | cut -d ' ' -f 1)" "${release}"
  } >"${dir}/blender-${release}.sha256"
}

# Writes the autoindex listing $1 (index or a series such as 4.5) that links each remaining argument.
make_listing() {
  local listing="$1"
  local name
  shift
  {
    printf '<html><head><title>Index of /release/</title></head><body><pre><a href="../">../</a>\n'
    for name in "$@"; do printf '<a href="%s">%s</a>  22-Oct-2026 01:35  1M\n' "${name}" "${name}"; done
    printf '</pre></body></html>\n'
  } >"${FIXTURE_DIR}/listings/${listing}.html"
}

# Succeeds when the installer fails for VERSION $1, with _REMOTE_USER $3 when given, printing a message matching $2.
fails_with() {
  if run_installer "$1" "${3-}"; then
    printf 'the installer accepted version "%s"\n' "$1" >&2
    return 1
  fi
  grep -q -- "$2" "${FIXTURE_DIR}/output"
}

# Succeeds when the installer fails for VERSION $1 with a message matching $2 and Blender still reports release $3.
failed_and_kept() {
  fails_with "$1" "$2" && reports_release "$3"
}

# Prints the number of requests the fixture has answered so far.
requests() {
  wc -l <"${FIXTURE_DIR}/requests"
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

make_release 4.5.2
make_release 4.5.15
make_release 5.0.0
make_release 5.0.1
make_listing index GPL-license.txt Blender2.80/ Blender4.5/ Blender5.0/ Blender5.1/ blender2.04-ipaq.zip
make_listing 4.5 blender-4.5.10-linux-x64.tar.xz blender-4.5.10.sha256 blender-4.5.15-linux-x64.tar.xz \
  blender-4.5.15.sha256 blender-4.5.15-windows-x64.zip blender-4.5.2-linux-x64.tar.xz blender-4.5.2.sha256 \
  blender-4.5.9-linux-x64.tar.xz blender-4.5.9.sha256
make_listing 5.0 blender-5.0.0-linux-x64.tar.xz blender-5.0.0.sha256 blender-5.0.1-linux-x64.tar.xz
make_listing 5.1 blender-5.1.0-windows-x64.zip

before="$(requests)"
stub_package_manager
for value in '' latest- v5.2.3 5.2-lts 5.2.3.1 4 05.2 4.1 3.6.5 garbage; do
  check "version \"${value}\" fails naming the accepted forms" \
    fails_with "${value}" "option version is \"${value}\".*use latest, a series"
done
check "invalid versions fail before any request" test "$(requests)" = "${before}"
check "invalid versions fail before installing packages" test ! -e "${FIXTURE_DIR}/apt-get"
rm "${FIXTURE_DIR}/bin/dpkg-query" "${FIXTURE_DIR}/bin/apt-get"

previous_umask="$(umask)"
umask 077
check "an exact release installs" run_installer 4.5.2
umask "${previous_umask}"
check "the exact release is active" reports_release 4.5.2
check "a non-root user runs Blender installed under a restrictive umask" \
  runuser --user nobody -- "${LINK}" --version
check "an exact release needs no listing" bash -c "! grep -q '/$' '${FIXTURE_DIR}/requests'"

check "a series selects its numerically highest release" run_installer 4.5
check "the series release is 4.5.15, not 4.5.9" reports_release 4.5.15
check "a release whose checksum file is not listed is skipped" run_installer 5.0
check "the series release is 5.0.0" reports_release 5.0.0
check "latest skips a newest series without a release" run_installer latest
check "latest selects 5.0.0" reports_release 5.0.0

check "an unavailable series listing fails naming its URL and keeps the installation" \
  failed_and_kept 4.4 'https://download.blender.org/release/Blender4.4/' 5.0.0
check "a series without a qualifying release fails naming its listing" \
  failed_and_kept 5.1 'Blender5.1/ names no Linux x64 release' 5.0.0
cp "${FIXTURE_DIR}/listings/index.html" "${FIXTURE_DIR}/index.saved"
make_listing index Blender2.80/ Blender5.1/
check "latest without a qualifying release fails naming the listing" \
  failed_and_kept latest 'release/ names no Linux x64 release of 4.2 or later' 5.0.0
mv "${FIXTURE_DIR}/index.saved" "${FIXTURE_DIR}/listings/index.html"
check "an unavailable exact release fails naming the archive" \
  failed_and_kept 4.5.99 'cannot download https://download.blender.org/release/Blender4.5/blender-4.5.99-linux' \
    5.0.0

for mode in network:'cannot read the release listing' redirect:'cannot read the release listing' \
  missing_checksum:'cannot download .*blender-4.5.15.sha256' missing_entry:'holds 0 entries' \
  duplicate:'holds 2 entries' corrupt:'does not match blender-4.5.15.sha256'; do
  printf '%s\n' "${mode%%:*}" >"${FIXTURE_DIR}/mode"
  check "a ${mode%%:*} failure stops the installation and keeps the previous release" \
    failed_and_kept 4.5 "${mode#*:}" 5.0.0
done
printf 'redirect\n' >"${FIXTURE_DIR}/mode"
check "a redirected archive request fails naming the URL" \
  failed_and_kept 4.5.15 'cannot download https://download.blender.org/release/Blender4.5/blender-4.5.15-linux' \
    5.0.0
check "every request went to download.blender.org" \
  bash -c "! grep -v '^https://download.blender.org/release/' '${FIXTURE_DIR}/requests'"
printf 'normal\n' >"${FIXTURE_DIR}/mode"

make_release 4.5.15 incompatible
check "a release that cannot run fails naming it and keeps the previous release" \
  failed_and_kept 4.5.15 'Blender 4.5.15 cannot run on this image' 5.0.0
make_release 4.5.15 active_failure
check "a failed activation restores the previous release" \
  failed_and_kept 4.5.15 'activated Blender 4.5.15 does not report' 5.0.0
check "a failed activation restores the link" link_targets_executable
make_release 4.5.15

check "an upgrade succeeds" run_installer 5.0.1
check "the upgrade is active" reports_release 5.0.1
check "a downgrade succeeds" run_installer 4.5.2
check "the downgrade is active" reports_release 4.5.2
check "no staging directory is left in /opt" bash -c '! compgen -G "/opt/.blender-feature.*"'

touch "${TREE}/sentinel"
before="$(requests)"
check "the installed release installs again" run_installer 4.5.2
check "a healthy installation of the same release is kept" test -f "${TREE}/sentinel"
check "the same release is not downloaded again" \
  bash -c "! tail -n +$((before + 1)) '${FIXTURE_DIR}/requests' | grep -q 'tar.xz$'"
check "latest is resolved anew" run_installer latest
check "latest replaces the installation with 5.0.0" reports_release 5.0.0

printf '#!/bin/sh\nexit 1\n' >"${TREE}/blender"
printf 'corrupt\n' >"${FIXTURE_DIR}/mode"
check "a failed repair reports the failure" fails_with 5.0.0 'does not match'
check "a failed repair keeps the unhealthy tree" grep -q 'exit 1' "${TREE}/blender"
printf 'normal\n' >"${FIXTURE_DIR}/mode"
check "an unhealthy installation of the same release is repaired" run_installer 5.0.0
check "the repaired release runs" reports_release 5.0.0

mv "${LINK}" "${FIXTURE_DIR}/link"
cat >"${LINK}" <<'FOREIGN'
#!/bin/sh
# A foreign installation reporting the requested release.
touch "${FIXTURE_DIR}/foreign_executed"
printf 'Blender 5.0.0\n'
FOREIGN
chmod +x "${LINK}"
check "a foreign command at the link path fails the installation" fails_with 5.0.0 "${LINK} is occupied"
check "the foreign command is kept" grep -q foreign "${LINK}"
check "the foreign command is never executed" test ! -e "${FIXTURE_DIR}/foreign_executed"
rm "${LINK}"
ln -s /does/not/exist "${LINK}"
check "a broken link at the link path fails the installation" fails_with 5.0.0 "${LINK} is occupied"
check "the broken link is kept" test "$(readlink "${LINK}")" = /does/not/exist
rm "${LINK}"
mv "${FIXTURE_DIR}/link" "${LINK}"
mv "${TREE}/.devcontainer-feature-blender" "${FIXTURE_DIR}/marker"
check "a tree without the marker is unmanaged" fails_with 5.0.0 "${TREE} is unmanaged"
mv "${FIXTURE_DIR}/marker" "${TREE}/.devcontainer-feature-blender"
printf '#!/bin/sh\necho foreign\n' >"${FIXTURE_DIR}/bin/blender"
chmod +x "${FIXTURE_DIR}/bin/blender"
check "a foreign blender elsewhere on PATH fails the installation" \
  fails_with 5.0.0 "${FIXTURE_DIR}/bin/blender conflicts with this feature"
rm "${FIXTURE_DIR}/bin/blender"
useradd --create-home blender_probe
mkdir -p /home/blender_probe/.local/bin
printf '#!/bin/sh\necho foreign\n' >/home/blender_probe/.local/bin/blender
chmod +x /home/blender_probe/.local/bin/blender
check "a foreign blender on the remote user's PATH fails the installation" \
  fails_with 5.0.0 '/home/blender_probe/.local/bin/blender conflicts with this feature' blender_probe
userdel --remove blender_probe
check "the managed installation is still accepted" run_installer 5.0.0

before="$(requests)"
stub_package_manager
cp -L /etc/os-release "${FIXTURE_DIR}/os-release"
printf 'ID=alpine\n' >/etc/os-release
check "an unsupported distribution is identified" fails_with 5.0.0 'unsupported distribution "alpine"'
cat "${FIXTURE_DIR}/os-release" >/etc/os-release
ln -s /does/not/exist /lib/ld-musl-x86_64.so.1
printf '#!/bin/sh\nexit 1\n' >"${FIXTURE_DIR}/bin/getconf"
chmod +x "${FIXTURE_DIR}/bin/getconf"
check "a musl-based image is rejected" fails_with 5.0.0 '"debian" is musl-based, which is unsupported'
rm "${FIXTURE_DIR}/bin/getconf"
printf '#!/bin/sh\necho aarch64\n' >"${FIXTURE_DIR}/bin/uname"
chmod +x "${FIXTURE_DIR}/bin/uname"
check "arm64 fails stating that Blender publishes no build for it" \
  fails_with 5.0.0 'unsupported architecture aarch64: Blender publishes no Linux build'
rm "${FIXTURE_DIR}/bin/uname"
# A 32-bit image on an amd64 kernel: uname still reports x86_64, the package manager reports i386.
printf '#!/bin/sh\necho i386\n' >"${FIXTURE_DIR}/bin/dpkg"
chmod +x "${FIXTURE_DIR}/bin/dpkg"
check "an i386 image on an amd64 kernel fails stating that Blender publishes no build for it" \
  fails_with 5.0.0 'unsupported architecture i386: Blender publishes no Linux build'
rm "${FIXTURE_DIR}/bin/dpkg"
check "unsupported platforms fail before any request" test "$(requests)" = "${before}"
check "unsupported platforms fail before installing packages" test ! -e "${FIXTURE_DIR}/apt-get"
rm "${FIXTURE_DIR}/bin/dpkg-query" "${FIXTURE_DIR}/bin/apt-get"
check "a glibc image with a musl loader installs" run_installer 5.0.0
rm /lib/ld-musl-x86_64.so.1
check "every request is HTTPS-only and follows no redirect" \
  bash -c "! grep -v -e '--proto =https.*--location --max-redirs 0' '${FIXTURE_DIR}/arguments'"

reportResults
