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

# The last run printed an error message that holds the text $1: a line with the prefix install.sh gives its error
# messages, and not one it only logs.
printed_error() {
  local line
  while IFS= read -r line; do
    if [[ "${line}" == "pacman-packages: error: "*"$1"* ]]; then return 0; fi
  done <<<"${install_output}"
  printf 'install.sh printed no line that starts with "pacman-packages: error: " and contains "%s"\n' "$1" >&2
  return 1
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

# The stand-in for pacman and what it records of its last call. Outside /tmp, so that a listing of /tmp shows only what
# install.sh itself creates there.
readonly STAND_IN_DIR="/opt/pacman-packages-test/bin"
readonly RECORD_DIR="/opt/pacman-packages-test/record"

# The arguments of the one pacman call install.sh makes without parallelDownloads, before the entries. The scripts that
# source this file read it.
# shellcheck disable=SC2034
readonly PACMAN_ARGUMENTS=(--sync --refresh --sysupgrade --needed --noconfirm --)

# Creates the stand-in that run_install_with_stand_in puts before pacman on PATH. It records its arguments, its
# environment, and, when it is called with --config, the configuration file and what pacman-conf resolves from it. Then
# it runs the real pacman with the same arguments ($1 is "real"), or exits 0 without it ($1 is "only").
create_stand_in() {
  local last_line="exit 0"
  if [[ "$1" == real ]]; then last_line='exec /usr/bin/pacman "$@"'; fi
  mkdir -p "${STAND_IN_DIR}" "${RECORD_DIR}"
  cat >"${STAND_IN_DIR}/pacman" <<EOF
#!/bin/sh
echo call >>"${RECORD_DIR}/calls"
printf '%s\n' "\$@" >"${RECORD_DIR}/arguments"
env >"${RECORD_DIR}/environment"
if [ "\$1" = --config ]; then
  cat "\$2" >"${RECORD_DIR}/configuration"
  stat -c '%a %U' "\$2" >"${RECORD_DIR}/configuration_mode"
  /usr/bin/pacman-conf --config "\$2" >"${RECORD_DIR}/resolved"
  /usr/bin/pacman-conf --config "\$2" --repo-list >"${RECORD_DIR}/repositories"
fi
${last_line}
EOF
  chmod +x "${STAND_IN_DIR}/pacman"
}

# Runs install.sh as run_install does, with the stand-in before pacman on PATH and an empty record.
run_install_with_stand_in() {
  rm -f "${RECORD_DIR:?}"/*
  run_install PATH="${STAND_IN_DIR}:${PATH}" "$@"
}

# The last run called pacman $1 times.
pacman_was_called() {
  local calls=0
  if [[ -e "${RECORD_DIR}/calls" ]]; then calls="$(wc -l <"${RECORD_DIR}/calls")"; fi
  if [[ "${calls}" -ne "$1" ]]; then
    echo "pacman was called ${calls} times, not $1" >&2
    return 1
  fi
}

# The last run's pacman call had exactly the arguments given.
pacman_received() {
  if [[ "$(<"${RECORD_DIR}/arguments")" != "$(printf '%s\n' "$@")" ]]; then
    printf 'pacman received: %s\n' "$(tr '\n' ' ' <"${RECORD_DIR}/arguments")" >&2
    return 1
  fi
}

# The last run's pacman call named a configuration file from which pacman resolves ParallelDownloads as $1.
resolved_parallel_downloads() {
  if ! grep -qx "ParallelDownloads = $1" "${RECORD_DIR}/resolved"; then
    echo "the configuration of the pacman call does not resolve ParallelDownloads as $1:" >&2
    grep ParallelDownloads "${RECORD_DIR}/resolved" >&2
    return 1
  fi
}

# What pacman resolved from the configuration file of the last run's pacman call equals the listing $1, which
# pacman-conf printed for /etc/pacman.conf, in every line but the ParallelDownloads one, and in their order.
resolved_configuration_equals_except_parallel_downloads() {
  local image resolved
  image="$(grep -v '^ParallelDownloads = ' <<<"$1")"
  resolved="$(grep -v '^ParallelDownloads = ' "${RECORD_DIR}/resolved")"
  if [[ "${resolved}" != "${image}" ]]; then
    echo "the resolved configurations differ in:" >&2
    comm -3 <(sort <<<"${image}") <(sort <<<"${resolved}") >&2
    return 1
  fi
}

# Prints the path of the configuration file the last run's pacman call named.
recorded_configuration_path() {
  sed -n 2p "${RECORD_DIR}/arguments"
}

# Prints every file and directory under /tmp, where install.sh creates its temporary configuration.
temporary_files() {
  find /tmp -mindepth 1 | sort
}

# /tmp holds what the listing $1 holds and nothing else.
temporary_files_are() {
  if [[ "$(temporary_files)" != "$1" ]]; then
    echo "/tmp changed; before and after differ in:" >&2
    comm -3 <(printf '%s\n' "$1") <(temporary_files) >&2
    return 1
  fi
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
