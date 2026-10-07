# shellcheck shell=bash
# Sourced by the dnf-packages scenario scripts that run install.sh themselves. A test run puts this checkout's
# src/dnf-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer). The scripts
# run it with the options as environment variables, as the devcontainer CLI does at image build time, and assert the
# exit status, the output, and the state of the container. Every compatibility image runs its scenarios as root, so
# nothing here changes user. This file holds the run and the assertions several of the scripts use; an assertion that
# fails says what it found.

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
