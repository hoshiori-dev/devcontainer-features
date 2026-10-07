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
