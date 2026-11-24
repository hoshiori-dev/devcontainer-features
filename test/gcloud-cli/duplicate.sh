#!/usr/bin/env bash
# Install-twice test: installed first with non-default options (older version and components), then with defaults
# (version latest, components empty). Option values arrive as <OPTION> and <OPTION>__DEFAULT.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

readonly STATE_DIR="/var/lib/gcloud-cli"

first_install_differed() {
  [[ "${VERSION__DEFAULT:-}" == latest && -n "${VERSION:-}" && "${VERSION:-}" != latest ]]
}

current_sdk_version() {
  gcloud version | awk '/^Google Cloud SDK / { print $4; exit }'
}

# After the second install with defaults (latest), gcloud must be newer than the first pinned version.
moved_to_latest() {
  local current
  current="$(current_sdk_version)"
  [[ -n "${current}" && "${current}" != "${VERSION:-}" ]] \
    && [[ "$(printf '%s\n%s\n' "${VERSION:-}" "${current}" | sort -V | head -n 1)" == "${VERSION:-}" ]]
}

repo_defined_once() {
  local defs=()
  if command -v apt-get >/dev/null 2>&1; then
    readarray -t defs < <(
      grep -hF "packages.cloud.google.com/apt" /etc/apt/sources.list /etc/apt/sources.list.d/*.list \
        /etc/apt/sources.list.d/*.sources 2>/dev/null
    )
    ((${#defs[@]} == 1))
  elif command -v dnf >/dev/null 2>&1; then
    readarray -t defs < <(grep -hE '^baseurl=.*packages\.cloud\.google\.com' /etc/yum.repos.d/*.repo 2>/dev/null)
    ((${#defs[@]} == 1))
  fi
}

packages_in_lockstep() {
  local main_ver pkg ver kver
  if command -v apt-get >/dev/null 2>&1; then
    # Single-quoted format strings pass literal dpkg-query placeholders without shell expansion.
    # shellcheck disable=SC2016
    main_ver="$(
      dpkg-query -W -f='${db:Status-Status}\t${Version}\n' google-cloud-cli | awk '$1 == "installed" { print $2; exit }'
    )"
    for pkg in $(
      # Single-quoted format strings pass literal dpkg-query placeholders without shell expansion.
      # shellcheck disable=SC2016
      dpkg-query -W -f='${db:Status-Status}\t${Package}\n' 'google-cloud-cli-*' 2>/dev/null \
        | awk '$1 == "installed" { print $2 }' || true
    ); do
      # Single-quoted format string passes literal ${Version} placeholder to dpkg-query.
      # shellcheck disable=SC2016
      ver="$(dpkg-query -W -f='${Version}' "${pkg}")"
      [[ "${ver}" == "${main_ver}" ]] || return 1
    done
    # Single-quoted format strings pass literal dpkg-query placeholders without shell expansion.
    # shellcheck disable=SC2016
    kver="$(
      dpkg-query -W -f='${db:Status-Status}\t${Version}\n' kubectl 2>/dev/null \
        | awk '$1 == "installed" { print $2; exit }' || true
    )"
    if [[ -n "${kver}" ]]; then
      [[ "${kver}" == "1:${main_ver}" ]] || return 1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    main_ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}' google-cloud-cli)"
    for pkg in $(rpm -qa --qf '%{NAME}\n' 'google-cloud-cli-*' 2>/dev/null || true); do
      ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "${pkg}")"
      [[ "${ver}" == "${main_ver}" ]] || return 1
    done
    if rpm -q kubectl >/dev/null 2>&1; then
      [[ "$(rpm -q --qf '%{VERSION}-%{RELEASE}' kubectl)" == "${main_ver}" ]] || return 1
    fi
  fi
}

no_temp_residue() {
  ! compgen -G '/tmp/gcloud-cli-gnupg.*' >/dev/null \
    && ! compgen -G '/tmp/gcloud-cli-build.*' >/dev/null \
    && ! compgen -G '/usr/local/share/.gcloud-cli-install.*' >/dev/null
}

check "the first install used pinned version ${VERSION:-unset}, not latest" first_install_differed
check "the second install moved gcloud to latest beyond ${VERSION:-unset}" moved_to_latest
check "installed Google Cloud packages moved in lockstep" packages_in_lockstep
check "repository definition is not duplicated" repo_defined_once
check "creation-time initialization succeeds after two installs" /usr/local/share/gcloud-cli-feature/initialize
check "user .config/gcloud still links into the state volume" \
  test "$(readlink -f "${HOME}/.config/gcloud")" = "${STATE_DIR}/config"
check "no temporary GnuPG or staging directories remain" no_temp_residue

reportResults
