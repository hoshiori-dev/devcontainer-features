# shellcheck shell=bash
# Sourced by the zypper-packages scenario scripts that run install.sh themselves. A test run puts this checkout's
# src/zypper-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer). The
# scripts run it with the options as environment variables, as the devcontainer CLI does at image build time, and
# assert the exit status, the output, and the state of the container. Both compatibility images run their scenarios as
# root, so nothing here changes user. This file holds the run and the assertions several of the scripts use; an
# assertion that fails says what it found. The images ship no find, so files are listed with globs.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER

install_status=0
install_output=""
install_seconds=0

# Runs install.sh with the environment assignments given (PACKAGES=bc CLEANUP=none) and prints its output. Keeps the
# exit status in install_status, stdout with stderr in install_output, and the whole seconds the run took in
# install_seconds.
run_install() {
  local started="${SECONDS}"
  install_status=0
  install_output="$(env "$@" "${INSTALLER}" 2>&1)" || install_status=$?
  install_seconds="$((SECONDS - started))"
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

# The last run did not print the text $1.
did_not_print() {
  if [[ "${install_output}" == *"$1"* ]]; then
    printf 'the output of install.sh contains "%s"\n' "$1" >&2
    return 1
  fi
}

# A line of the last run's output matches the extended regular expression $1.
output_matches() {
  grep --extended-regexp --quiet -- "$1" <<<"${install_output}"
}

installed() {
  if ! rpm -q "$1" >/dev/null; then
    echo "$1 is not installed" >&2
    return 1
  fi
}

not_installed() {
  if rpm -q "$1" >/dev/null; then
    echo "$1 is installed" >&2
    return 1
  fi
}

# Prints the version and release of the installed package $1.
version_of() {
  rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"
}

has_version() {
  if [[ "$(version_of "$1")" != "$2" ]]; then
    echo "$1 is at $(version_of "$1"), not $2" >&2
    return 1
  fi
}

# Prints a digest of the names and versions in the RPM database, signing keys included.
rpm_database() {
  rpm -qa | sort | sha256sum
}

# The RPM database still has the digest $1.
rpm_database_is() {
  if [[ "$(rpm_database)" != "$1" ]]; then
    echo "the installed packages changed" >&2
    return 1
  fi
}

# Prints the parsed metadata caches that hold data.
parsed_metadata() {
  local solv_file
  for solv_file in /var/cache/zypp/solv/*/solv; do
    if [[ -s "${solv_file}" ]]; then printf '%s\n' "${solv_file}"; fi
  done
}

has_metadata() {
  if [[ -z "$(parsed_metadata)" ]]; then
    echo "/var/cache/zypp/solv holds no parsed metadata" >&2
    return 1
  fi
}

no_metadata() {
  if [[ -n "$(parsed_metadata)" ]]; then
    echo "/var/cache/zypp/solv holds parsed metadata" >&2
    return 1
  fi
}

# Prints a digest of the zypp configuration: the content of every file in /etc/zypp and in its directories of
# repository definitions, service definitions, and trusted keys.
zypp_configuration() {
  local file
  for file in /etc/zypp/* /etc/zypp/repos.d/* /etc/zypp/services.d/* /etc/zypp/trusted.d/* \
    /etc/zypp/trustedkeys.d/*; do
    if [[ -f "${file}" ]]; then sha256sum "${file}"; fi
  done | sort | sha256sum
}

# The zypp configuration still has the digest $1.
zypp_configuration_is() {
  if [[ "$(zypp_configuration)" != "$1" ]]; then
    echo "a file under /etc/zypp changed" >&2
    return 1
  fi
}

# Prints a digest of every directory libzypp reads configuration from: the name of all that /etc/zypp, /usr/etc/zypp,
# and /run/zypp hold, and the content of each file.
libzypp_configuration() {
  (
    shopt -s globstar nullglob dotglob
    for path in /etc/zypp/** /usr/etc/zypp/** /run/zypp/**; do
      if [[ -f "${path}" ]]; then sha256sum "${path}"; else printf '%s\n' "${path}"; fi
    done
  ) | sha256sum
}

# The directories libzypp reads configuration from still have the digest $1.
libzypp_configuration_is() {
  if [[ "$(libzypp_configuration)" != "$1" ]]; then
    echo "a file or directory under /etc/zypp, /usr/etc/zypp, or /run/zypp changed" >&2
    return 1
  fi
}

# Nothing is left of the feature's temporary configuration file: the images have no /run/zypp of their own.
no_override_left() {
  if [[ -e /run/zypp ]]; then
    echo "/run/zypp exists" >&2
    return 1
  fi
}

# Prints the alias of the enabled repository whose alias ends in $1. Leap's aliases carry a service prefix, so the
# scripts read an alias when they run instead of fixing it.
enabled_alias() {
  zypper --xmlout --non-interactive --no-refresh repos \
    | sed -n "/enabled=\"1\"/s/.*alias=\"\\([^\"]*$1\\)\".*/\\1/p"
}

# Prints the repositories of which zypper's cache holds raw metadata, one per line.
raw_metadata_repositories() {
  local directory
  for directory in /var/cache/zypp/raw/*; do
    if [[ -d "${directory}" ]]; then printf '%s\n' "${directory##*/}"; fi
  done
}

# zypper's cache holds raw metadata of exactly the repositories given.
raw_metadata_only_of() {
  local expected
  expected="$(printf '%s\n' "$@" | sort)"
  if [[ "$(raw_metadata_repositories | sort)" != "${expected}" ]]; then
    printf 'raw metadata is cached of: %s\n' "$(raw_metadata_repositories | tr '\n' ' ')" >&2
    return 1
  fi
}

no_raw_metadata() {
  if [[ -n "$(raw_metadata_repositories)" ]]; then
    printf 'raw metadata is cached of: %s\n' "$(raw_metadata_repositories | tr '\n' ' ')" >&2
    return 1
  fi
}

# Prints the package files in zypper's cache.
package_files() {
  (
    shopt -s globstar nullglob
    for file in /var/cache/zypp/packages/**/*.rpm; do printf '%s\n' "${file}"; done
  )
}

no_package_files() {
  if [[ -n "$(package_files)" ]]; then
    echo "zypper's cache holds package files" >&2
    return 1
  fi
}

# The last run took at least $1 whole seconds.
took_at_least() {
  if [[ "${install_seconds}" -lt "$1" ]]; then
    echo "install.sh took ${install_seconds} s, less than $1 s" >&2
    return 1
  fi
}

# The last run took less than $1 whole seconds.
took_less_than() {
  if [[ "${install_seconds}" -ge "$1" ]]; then
    echo "install.sh took ${install_seconds} s, not less than $1 s" >&2
    return 1
  fi
}
