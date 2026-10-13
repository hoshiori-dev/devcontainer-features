# shellcheck shell=bash
# Sourced by the dnf-packages scenario scripts that run install.sh themselves. A test run puts this checkout's
# src/dnf-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer). The scripts
# run it with the options as environment variables, as the devcontainer CLI does at image build time, and assert the
# exit status, the output, and the state of the container. Every compatibility image runs its scenarios as root, so
# nothing here changes user. This file holds the run and the assertions several of the scripts use; an assertion that
# fails says what it found.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
# Where the dnf that record_dnf_calls creates writes its calls, and a PATH on which it precedes the image's dnf.
readonly DNF_CALLS="/tmp/dnf-calls"
readonly RECORDING_PATH="/tmp/recording-dnf:/usr/sbin:/usr/bin:/sbin:/bin"

install_status=0
install_output=""

# Puts a dnf on RECORDING_PATH that adds one line to DNF_CALLS for each call, "CALL [argument] [argument] ...", and then
# runs the image's dnf with the same arguments.
record_dnf_calls() {
  local dnf
  dnf="$(command -v dnf)"
  mkdir -p "${RECORDING_PATH%%:*}"
  cat >"${RECORDING_PATH%%:*}/dnf" <<RECORDER
#!/bin/sh
printf 'CALL' >>${DNF_CALLS}
for argument do printf ' [%s]' "\${argument}" >>${DNF_CALLS}; done
printf '\n' >>${DNF_CALLS}
exec ${dnf} "\$@"
RECORDER
  chmod +x "${RECORDING_PATH%%:*}/dnf"
}

# Runs install.sh like run_install, with the recording dnf first on PATH and DNF_CALLS holding the calls of this run
# only.
run_recorded_install() {
  rm -f "${DNF_CALLS}"
  run_install PATH="${RECORDING_PATH}" "$@"
}

# Prints the install calls of the last recorded run; fails when it made none.
install_calls() {
  grep --fixed-strings '[install]' "${DNF_CALLS}"
}

# Every install call of the last recorded run carries the argument $1.
install_call_has() {
  local calls
  calls="$(install_calls)" || return
  if grep --invert-match --fixed-strings --quiet -e "[$1]" <<<"${calls}"; then
    printf 'the install call does not carry %s:\n%s\n' "$1" "${calls}" >&2
    return 1
  fi
}

# No install call of the last recorded run matches the extended regular expression $1.
install_call_lacks() {
  local calls
  calls="$(install_calls)" || return
  if grep --extended-regexp --quiet -e "$1" <<<"${calls}"; then
    printf 'the install call matches %s:\n%s\n' "$1" "${calls}" >&2
    return 1
  fi
}

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

# A line of the last run's output matches the extended regular expression $1.
output_matches() {
  grep --extended-regexp --quiet -- "$1" <<<"${install_output}"
}

installed() {
  if ! rpm -q "$1" >/dev/null 2>&1; then
    echo "$1 is not installed" >&2
    return 1
  fi
}

not_installed() {
  if rpm -q "$1" >/dev/null 2>&1; then
    echo "$1 is installed" >&2
    return 1
  fi
}

# Prints the version and release of the installed package $1.
version_of() {
  rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"
}

# The installed package $1 has the version and release $2.
has_version() {
  if [[ "$(version_of "$1")" != "$2" ]]; then
    echo "$1 is at $(version_of "$1"), not $2" >&2
    return 1
  fi
}

# Prints a digest of the RPM database: every installed package with its version, release, and architecture, and every
# key in the RPM keyring.
rpm_database() {
  local packages
  packages="$(rpm -qa)"
  sort <<<"${packages}" | sha256sum
}

# The RPM database still has the digest $1.
rpm_database_is() {
  if [[ "$(rpm_database)" != "$1" ]]; then
    echo "the installed packages or the keys in the RPM keyring changed" >&2
    return 1
  fi
}

# Prints the repository metadata in dnf's cache. dnf4 keeps its cache under /var/cache/dnf and dnf5 under
# /var/cache/libdnf5, and one of the two may be missing, so the callers judge what find prints, never its status.
cached_metadata() {
  find /var/cache/dnf /var/cache/libdnf5 -name repomd.xml 2>/dev/null || true
}

has_metadata() {
  if [[ -z "$(cached_metadata)" ]]; then
    echo "dnf's cache holds no repository metadata" >&2
    return 1
  fi
}

no_metadata() {
  if [[ -n "$(cached_metadata)" ]]; then
    echo "dnf's cache holds repository metadata" >&2
    return 1
  fi
}

# Prints the metadata of the repository $1 in dnf's cache, whose directories are named "<identifier>-<16 hex digits>".
cached_metadata_of() {
  local metadata
  metadata="$(cached_metadata)"
  grep --extended-regexp "/$1-[0-9a-f]{16}/repodata/" <<<"${metadata}" || true
}

has_metadata_of() {
  if [[ -z "$(cached_metadata_of "$1")" ]]; then
    echo "dnf's cache holds no repository metadata of $1" >&2
    return 1
  fi
}

no_metadata_of() {
  if [[ -n "$(cached_metadata_of "$1")" ]]; then
    echo "dnf's cache holds repository metadata of $1" >&2
    return 1
  fi
}

# Prints the downloaded package files in dnf's cache, of every repository.
cached_package_files() {
  find /var/cache/dnf /var/cache/libdnf5 -name '*.rpm' 2>/dev/null || true
}

no_package_files() {
  if [[ -n "$(cached_package_files)" ]]; then
    echo "dnf's cache holds downloaded package files" >&2
    return 1
  fi
}

# Prints the downloaded package files of the repository $1 in dnf's cache, which keeps them in the directory
# "<identifier>-<16 hex digits>/packages".
cached_package_files_of() {
  local files
  files="$(cached_package_files)"
  grep --extended-regexp "/$1-[0-9a-f]{16}/packages/" <<<"${files}" || true
}

has_package_files_of() {
  if [[ -z "$(cached_package_files_of "$1")" ]]; then
    echo "dnf's cache holds no downloaded package file of $1" >&2
    return 1
  fi
}

# dnf's cache holds downloaded package files, and every one of them is of the repository $1.
only_package_files_of() {
  local files
  files="$(cached_package_files)"
  if [[ -z "${files}" || "${files}" != "$(cached_package_files_of "$1")" ]]; then
    printf 'the downloaded package files in the cache are not those of %s alone:\n%s\n' "$1" "${files}" >&2
    return 1
  fi
}

# Prints every repository the image configures with its state, "<identifier> enabled" or "<identifier> disabled", as
# dnf lists them without loading metadata.
repository_states() {
  local listing
  listing="$(dnf -q repolist --all)"
  awk 'NR > 1 { print $1, $NF }' <<<"${listing}" | sort
}

# The image enables and disables the same repositories as in the listing $1.
repository_states_are() {
  if [[ "$(repository_states)" != "$1" ]]; then
    echo "the repositories the image enables changed" >&2
    return 1
  fi
}

# Prints the keys in the RPM keyring.
rpm_keys() {
  local keys
  keys="$(rpm -q gpg-pubkey)" || true
  sort <<<"${keys}"
}

# The RPM keyring still holds exactly the keys $1.
rpm_keys_are() {
  if [[ "$(rpm_keys)" != "$1" ]]; then
    echo "the keys in the RPM keyring changed" >&2
    return 1
  fi
}

# Prints a digest of the dnf configuration: the names, types, modes, and link targets under /etc/dnf, /etc/yum.repos.d,
# and /etc/pki/rpm-gpg, and the content of every file there.
dnf_configuration() {
  local names contents
  names="$(find /etc/dnf /etc/yum.repos.d /etc/pki/rpm-gpg -printf '%p %y %m %l\n' | sort)"
  contents="$(find /etc/dnf /etc/yum.repos.d /etc/pki/rpm-gpg -type f -exec sha256sum {} + | sort)"
  printf '%s\n%s\n' "${names}" "${contents}" | sha256sum
}

# The dnf configuration still has the digest $1.
dnf_configuration_is() {
  if [[ "$(dnf_configuration)" != "$1" ]]; then
    echo "/etc/dnf, /etc/yum.repos.d, or /etc/pki/rpm-gpg changed" >&2
    return 1
  fi
}
