#!/usr/bin/env bash
# Scenario "fail_contract": debian:12 as root with the defaults installed; runs the installer again with recording
# stand-ins for curl and uname, and asserts every rejection and download failure the spec lists that a successful build
# cannot show ("Version outside the accepted forms", "Name outside the official forms", "Malformed latest-release
# redirect", "Release that does not exist", "Digest reported and not matching", "Archive without the executable",
# "Toolchain cannot be installed", "Toolchain download fails", "Failure over an existing installation", "Unsupported
# architecture", "musl image", "Unsupported distribution", the missing package manager, "Remote user that does not
# exist", "Group is the remote user's primary group", "Group has another member", "No tool for the group", a directory
# at a target path, and "Same options"). Each rejected run must exit non-zero with its message and leave the targets,
# packages, groups, and temporary directory as they were; a run rejected for its options or platform makes no request,
# and every request the installer makes carries curl's HTTPS-only flags for itself and its redirects.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

work_dir="$(mktemp -d /tmp/lean-fail-contract.XXXXXX)"
installer="$(dirname "$(readlink -f "$0")")/_feature/install.sh"
machine="$(uname -m)"
readonly work_dir installer machine
readonly stubs="${work_dir}/stubs"
readonly curl_log="${work_dir}/curl.log"
readonly output="${work_dir}/output"
readonly asset="elan-${machine}-unknown-linux-gnu.tar.gz"

cleanup() {
  rm -rf "${work_dir}"
}

# Prints everything a rejected run must leave as it was.
state() {
  stat -c '%i %Y %F' /usr/local/bin/elan
  /usr/local/bin/elan --version 2>/dev/null || true
  for proxy in lean lake leanc leanmake leanchecker leanpkg; do readlink "/usr/local/bin/${proxy}" || true; done
  find /usr/local/share/lean /usr/local/share/lean-feature /var/lib/lean -printf '%p %U %G %m\n' 2>/dev/null | sort
  find /usr/local/share /tmp -maxdepth 1 \( -name '.lean-elan-home.*' -o -name 'tmp.*' \) | sort
  # The format names dpkg-query fields, not shell variables.
  # shellcheck disable=SC2016
  dpkg-query -W -f '${Package} ${Version}\n' | md5sum
  md5sum /etc/group /etc/passwd
}

# Runs the installer as root with the stand-ins first on PATH; the arguments are NAME=value settings for the
# installer and the stand-ins. Keeps the output and returns the installer's status.
run_installer() {
  : >"${curl_log}"
  env PATH="${stubs}:${PATH}" CURL_LOG="${curl_log}" "$@" bash "${installer}" >"${output}" 2>&1
}

# Whether a run with the settings $2... fails with the message $1 and leaves the state as it was.
rejected() {
  local message="$1" before after
  shift
  before="$(state)"
  if run_installer "$@"; then
    cat "${output}"
    return 1
  fi
  after="$(state)"
  if ! grep -qF -- "${message}" "${output}"; then
    cat "${output}"
    return 1
  fi
  if [[ "${before}" != "${after}" ]]; then
    diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") || true
    return 1
  fi
}

# Whether a run with the settings $2... is rejected with the message $1, as rejected says, before any request.
rejected_before_any_request() {
  rejected "$@" CURL_MODE=refuse || return 1
  if [[ -s "${curl_log}" ]]; then
    cat "${curl_log}"
    return 1
  fi
}

# Whether every request the last run made carried the HTTPS-only flags, for the request and for its redirects.
requests_https_only() {
  local line
  [[ -s "${curl_log}" ]] || return 1
  while read -r line; do
    [[ "${line}" == *"--proto =https"* && "${line}" == *"--proto-redir =https"* ]] || return 1
  done <"${curl_log}"
}

# Links every command of the image into the directory $1, except the commands $2...; a PATH of that directory hides
# them.
link_commands_except() {
  local dir="$1" command name
  shift
  mkdir -p "${dir}"
  for command in /usr/local/sbin/* /usr/local/bin/* /usr/sbin/* /usr/bin/*; do
    name="${command##*/}"
    if [[ " $* " == *" ${name} "* || -e "${dir}/${name}" ]]; then continue; fi
    ln -s "${command}" "${dir}/${name}"
  done
}

trap cleanup EXIT
umask 022

# The curl stand-in records each call's arguments. CURL_MODE=refuse fails every call; real passes it on to curl;
# fixture answers the redirect query with CURL_REDIRECT, the release API with the file CURL_API, and the archive with
# the file CURL_ARCHIVE, failing as a missing file does when a setting is empty.
mkdir -p "${stubs}"
cat >"${stubs}/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${CURL_LOG}"
case "${CURL_MODE}" in
  refuse) exit 7 ;;
  real) exec /usr/bin/curl "$@" ;;
esac
out="" url=""
while (($#)); do
  case "$1" in
    --output) out="$2"; shift ;;
    https://*) url="$1" ;;
  esac
  shift
done
case "${url}" in
  */releases/latest) printf '%s' "${CURL_REDIRECT}" ;;
  https://api.github.com/*) [[ -n "${CURL_API}" ]] || exit 22; cp "${CURL_API}" "${out}" ;;
  *.tar.gz) [[ -n "${CURL_ARCHIVE}" ]] || exit 22; cp "${CURL_ARCHIVE}" "${out}" ;;
  *) exit 22 ;;
esac
STUB
cat >"${stubs}/uname" <<'STUB'
#!/bin/sh
if [ -n "${UNAME_MACHINE}" ]; then printf '%s\n' "${UNAME_MACHINE}"; exit 0; fi
exec /usr/bin/uname "$@"
STUB
chmod +x "${stubs}/curl" "${stubs}/uname"

# Fixtures: an archive with elan-init, one without it, and release API answers with a wrong digest and with none.
mkdir -p "${work_dir}/with" "${work_dir}/without"
cp /usr/local/bin/elan "${work_dir}/with/elan-init"
tar -czf "${work_dir}/with.tar.gz" -C "${work_dir}/with" elan-init
printf 'not elan\n' >"${work_dir}/without/README"
tar -czf "${work_dir}/without.tar.gz" -C "${work_dir}/without" README
zeros="$(printf '0%.0s' {1..64})"
printf '{\n  "assets": [\n    {\n      "name": "%s",\n      "digest": "sha256:%s"\n    }\n  ]\n}\n' \
  "${asset}" "${zeros}" >"${work_dir}/wrong-digest.json"
printf '{\n  "assets": [\n    {\n      "name": "%s",\n      "digest": null\n    }\n  ]\n}\n' \
  "${asset}" >"${work_dir}/no-digest.json"

# Version outside the accepted forms.
for value in 4.2 v4.2.4 4.2.4-rc1 "latest "; do
  check "elanVersion \"${value}\" is rejected before any request" \
    rejected_before_any_request "option elanVersion is \"${value}\"" ELANVERSION="${value}"
done
check "a release below 4.1.0 is rejected as older than the minimum" \
  rejected_before_any_request "older than 4.1.0" ELANVERSION=4.0.1

# Name outside the official forms.
for value in someone/lean4:v4.35.0 ../toolchain 4.35.0 leanprover-community/mathlib4:lean-toolchain " stable"; do
  check "defaultToolchain \"${value}\" is rejected before any request" \
    rejected_before_any_request "option defaultToolchain is \"${value}\"" DEFAULTTOOLCHAIN="${value}"
done
check "a preinstallToolchains path entry is rejected before any request" \
  rejected_before_any_request 'has the entry "/opt/toolchain"' PREINSTALLTOOLCHAINS="v4.35.0, /opt/toolchain"
check "a preinstallToolchains entry with a newline inside is rejected before any request" \
  rejected_before_any_request 'option preinstallToolchains has the entry' PREINSTALLTOOLCHAINS=$'v4.35.0\nv4.34.0'

# Unsupported architecture, musl image, Unsupported distribution.
check "an unsupported architecture is rejected before any request" \
  rejected_before_any_request 'unsupported architecture "riscv64"' UNAME_MACHINE=riscv64
touch "/lib/ld-musl-${machine}.so.1"
check "a musl image is rejected before any request" rejected_before_any_request 'need glibc'
rm "/lib/ld-musl-${machine}.so.1"
mv /etc/os-release "${work_dir}/os-release"
printf 'ID=gentoo\nPRETTY_NAME="Gentoo Linux"\n' >/etc/os-release
check "an unsupported distribution is rejected before any request" \
  rejected_before_any_request 'unsupported distribution "Gentoo Linux"'
mv "${work_dir}/os-release" /etc/os-release

# A missing prerequisite without the package manager.
link_commands_except "${work_dir}/no-git-no-apt" git apt-get
check "a missing package manager is named before any request" \
  rejected_before_any_request 'apt-get is not available to install git' PATH="${stubs}:${work_dir}/no-git-no-apt"

# Remote user that does not exist, Group is the remote user's primary group, Group has another member, No tool for
# the group.
check "a remote user that does not exist is named" \
  rejected_before_any_request 'remote user "nobody-here" does not exist' _REMOTE_USER=nobody-here
groupadd lean
useradd --gid lean leanprimary
check "the group lean as the remote user's primary group is rejected" \
  rejected_before_any_request 'group lean is the primary group of "leanprimary"' _REMOTE_USER=leanprimary
userdel leanprimary
useradd alice
useradd bob
usermod --append --groups lean alice
check "a group lean with another member is rejected, naming that account" \
  rejected_before_any_request 'group lean has other accounts: alice' _REMOTE_USER=bob
userdel alice
userdel bob
groupdel lean
useradd carol
link_commands_except "${work_dir}/no-groupadd" groupadd
check "a missing groupadd is named" \
  rejected_before_any_request 'groupadd is not available' _REMOTE_USER=carol PATH="${stubs}:${work_dir}/no-groupadd"
userdel carol

# A directory at a target path.
mv /usr/local/bin/elan "${work_dir}/elan"
mkdir /usr/local/bin/elan
check "a directory at /usr/local/bin/elan is rejected before any request" \
  rejected_before_any_request '/usr/local/bin/elan exists and is not a regular file or a link'
rmdir /usr/local/bin/elan
mv "${work_dir}/elan" /usr/local/bin/elan

# Malformed latest-release redirect, Release that does not exist, Digest reported and not matching, Archive without the
# executable: each fails after its requests and leaves the previous installation.
check "a malformed latest-release redirect fails, showing what it received" \
  rejected 'redirected to "https://github.com/leanprover/elan/releases/tag/nightly"' CURL_MODE=fixture \
  CURL_REDIRECT=https://github.com/leanprover/elan/releases/tag/nightly
check "the latest-release request is HTTPS only" requests_https_only
check "a release that does not exist fails, naming the version" \
  rejected "of elan 9.9.9" CURL_MODE=fixture ELANVERSION=9.9.9 CURL_ARCHIVE=
check "an archive that does not match GitHub's digest fails" \
  rejected 'does not match the digest GitHub reports' CURL_MODE=fixture ELANVERSION=4.2.3 \
  CURL_ARCHIVE="${work_dir}/with.tar.gz" CURL_API="${work_dir}/wrong-digest.json"
check "the archive and release API requests are HTTPS only, redirects included" requests_https_only
check "an archive without elan-init fails" \
  rejected 'holds no elan-init' CURL_MODE=fixture ELANVERSION=4.2.3 \
  CURL_ARCHIVE="${work_dir}/without.tar.gz" CURL_API="${work_dir}/no-digest.json"

# Toolchain cannot be installed: a toolchain upstream does not publish, through the real release index.
check "a toolchain upstream does not publish fails, naming it, and leaves nothing in the image" \
  rejected 'elan cannot install toolchain v9.9.9' CURL_MODE=real PREINSTALLTOOLCHAINS=v9.9.9

# Toolchain download fails: elan reaches the release index directly, and its download goes through a proxy that refuses
# connections. elanVersion names the installed release, so the installer itself makes no request.
installed_release="$(/usr/local/bin/elan --version)"
installed_release="${installed_release#elan }"
installed_release="${installed_release%% *}"
check "a toolchain whose download fails fails the install and leaves no partial toolchain" \
  rejected_before_any_request 'elan cannot install toolchain v4.35.0' ELANVERSION="${installed_release}" \
  PREINSTALLTOOLCHAINS=v4.35.0 https_proxy=http://127.0.0.1:9 HTTPS_PROXY=http://127.0.0.1:9 \
  no_proxy=release.lean-lang.org NO_PROXY=release.lean-lang.org

# Same options: no archive request, and elan unchanged.
before="$(stat -c '%i %Y' /usr/local/bin/elan)"
check "a second install with the same options succeeds" run_installer CURL_MODE=real
check "the second install downloads no elan release" bash -c "! grep -q 'releases/download' '${curl_log}'"
check "the second install leaves elan as it was" [ "$(stat -c '%i %Y' /usr/local/bin/elan)" == "${before}" ]

reportResults
