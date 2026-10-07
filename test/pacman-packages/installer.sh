# shellcheck shell=bash
# Sourced by the pacman-packages scenario scripts that run install.sh themselves. A test run puts this checkout's
# src/pacman-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer). The
# scripts run it with the options as environment variables, as the devcontainer CLI does at image build time, and assert
# the exit status, the output, and the state of the container. Every scenario's container runs as root, so no run needs
# sudo. This file holds the run and the assertions several of them use; an assertion that fails says what it found.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER

# Test-only host for previous package versions; the feature never reaches it.
readonly ARCHIVE="https://archive.archlinux.org/packages"

install_status=0
install_output=""

# Runs install.sh with the environment assignments given (PACKAGES=bc CLEANUP=none) and prints its output. Keeps the
# exit status in install_status and stdout with stderr in install_output.
run_install() {
  install_status=0
  install_output="$(env "$@" "${INSTALLER}" 2>&1)" || install_status=$?
  printf '%s\n' "${install_output}"
}

# The last run exited with status $1.
exited_with() {
  if [[ "${install_status}" -ne "$1" ]]; then
    echo "install.sh exited with status ${install_status}, not $1" >&2
    return 1
  fi
}

# The last run exited with a non-zero status.
failed() {
  if [[ "${install_status}" -eq 0 ]]; then
    echo "install.sh exited with status 0" >&2
    return 1
  fi
}

# The last run printed the text $1.
printed() {
  if [[ "${install_output}" != *"$1"* ]]; then
    printf 'the output of install.sh does not contain "%s"\n' "$1" >&2
    return 1
  fi
}

# The last run named the entry $1 as refused. Not the bare entry: "-" is also in the "pacman-packages:" prefix of every
# message, and quoted in the accepted characters the refusal spells out.
refused() {
  printed "refusing the entry '$1'"
}

installed() {
  if ! pacman -Qq -- "$1" >/dev/null 2>&1; then
    echo "$1 is not installed" >&2
    return 1
  fi
}

not_installed() {
  if pacman -Qq -- "$1" >/dev/null 2>&1; then
    echo "$1 is installed" >&2
    return 1
  fi
}

# Prints the installed version of the package $1.
version_of() {
  pacman -Q -- "$1" | awk '{print $2}'
}

has_version() {
  if [[ "$(version_of "$1")" != "$2" ]]; then
    echo "$1 is at $(version_of "$1"), not $2" >&2
    return 1
  fi
}

# Prints every installed package with its version, which changes with every package installed, upgraded, or removed.
local_database() {
  pacman -Q
}

# The installed packages and their versions are still the listing $1.
local_database_is() {
  if [[ "$(local_database)" != "$1" ]]; then
    echo "the installed packages changed; before and after differ in:" >&2
    comm -3 <(sort <<<"$1") <(local_database | sort) >&2
    return 1
  fi
}

has_sync_databases() {
  if [[ -z "$(find /var/lib/pacman/sync -name '*.db' -print -quit)" ]]; then
    echo "/var/lib/pacman/sync holds no sync database" >&2
    return 1
  fi
}

# The compatibility image ships no sync database, so a file found here was downloaded by a run.
no_sync_databases() {
  if [[ -n "$(find /var/lib/pacman/sync -mindepth 1 -print -quit)" ]]; then
    echo "/var/lib/pacman/sync holds a file" >&2
    return 1
  fi
}

# Downloads the sync databases, for the script's own queries.
download_sync_databases() {
  pacman -Sy >/dev/null
}

# Returns the container to the state the image ships in: no sync database and no downloaded package, so that a run of
# install.sh starts without them.
remove_caches() {
  rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*
}

# Prints the version the repositories offer of the package $1. Needs sync databases.
offered_version() {
  pacman -Si -- "$1" | sed -n 's/^Version *: //p' | head -n 1
}

# Prints the newest version of the package $1 in the Arch Linux Archive that is older than the one the repositories
# offer, and the URL of its package file. `pacman -U <url>` verifies the detached signature beside it under the image's
# SigLevel. Read when the test runs, so that no fixed version goes stale. Needs sync databases.
previous_version() {
  local current architecture listing file version best=""
  current="$(offered_version "$1")"
  architecture="$(pacman -Si -- "$1" | sed -n 's/^Architecture *: //p' | head -n 1)"
  listing="$(curl -fsSL --retry 2 -- "${ARCHIVE}/${1:0:1}/$1/")" || return
  while read -r file; do
    if [[ "${file}" != "$1-"*"-${architecture}.pkg.tar.zst" ]]; then continue; fi
    version="${file#"$1-"}"
    version="${version%"-${architecture}.pkg.tar.zst"}"
    # pkgver-pkgrel without an epoch, whose colon the listing would percent-encode.
    if [[ ! "${version}" =~ ^[A-Za-z0-9._+]+-[0-9.]+$ ]]; then continue; fi
    if [[ "$(vercmp "${version}" "${current}")" -ge 0 ]]; then continue; fi
    if [[ -z "${best}" || "$(vercmp "${version}" "${best}")" -gt 0 ]]; then best="${version}"; fi
  done < <(grep -o 'href="[^"]*"' <<<"${listing}" | sed 's/^href="//; s/"$//')
  if [[ -z "${best}" ]]; then
    echo "the Arch Linux Archive lists no version of $1 older than ${current}" >&2
    return 1
  fi
  echo "${best} ${ARCHIVE}/${1:0:1}/$1/$1-${best}-${architecture}.pkg.tar.zst"
}

# Prints a digest of the repository configuration: the content of /etc/pacman.conf and of the mirror list.
repository_configuration() {
  find /etc/pacman.conf /etc/pacman.d/mirrorlist -type f -exec sha256sum {} + | sort | sha256sum
}

# The repository configuration still has the digest $1.
repository_configuration_is() {
  if [[ "$(repository_configuration)" != "$1" ]]; then
    echo "/etc/pacman.conf or /etc/pacman.d/mirrorlist changed" >&2
    return 1
  fi
}
