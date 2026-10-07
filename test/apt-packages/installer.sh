# shellcheck shell=bash
# Sourced by the apt-packages scenario scripts that run install.sh themselves. A test run puts this checkout's
# src/apt-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer). The scripts
# run it as root with the options as environment variables, as the devcontainer CLI does at image build time, and assert
# the exit status, the output, and the state of the container. This file holds the run and the assertions several of
# them use; an assertion that fails says what it found.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER

install_status=0
install_output=""

# Runs a command as root: the scenario's remoteUser is not root on every image.
as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Runs install.sh as root with the environment assignments given (PACKAGES=bc CLEANUP=none) and prints its output.
# Keeps the exit status in install_status and stdout with stderr in install_output.
run_install() {
  install_status=0
  install_output="$(as_root env "$@" "${INSTALLER}" 2>&1)" || install_status=$?
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

# A line of the last run's output matches the extended regular expression $1; further grep options may follow.
output_matches() {
  grep --extended-regexp --quiet "${@:2}" -- "$1" <<<"${install_output}"
}

installed() {
  if [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" != "install ok installed" ]]; then
    echo "$1 is not installed" >&2
    return 1
  fi
}

not_installed() {
  if [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]; then
    echo "$1 is installed" >&2
    return 1
  fi
}

# Prints a digest of dpkg's status file, which changes with every package installed, removed, or reconfigured.
dpkg_status() {
  sha256sum /var/lib/dpkg/status
}

# dpkg's status file still has the digest $1.
dpkg_status_is() {
  if [[ "$(dpkg_status)" != "$1" ]]; then
    echo "dpkg's status file changed" >&2
    return 1
  fi
}

has_index() {
  if ! compgen -G '/var/lib/apt/lists/*_Packages*' >/dev/null; then
    echo "/var/lib/apt/lists holds no package index" >&2
    return 1
  fi
}

# Both compatibility images ship no package index, so a package list found here was fetched by a run.
no_index() {
  if compgen -G '/var/lib/apt/lists/*_Packages*' >/dev/null; then
    echo "/var/lib/apt/lists holds a package index" >&2
    return 1
  fi
}

# Prints a digest of the apt configuration: the names, types, modes, and link targets under /etc/apt and
# /usr/share/keyrings, and the content of every file there.
apt_configuration() {
  as_root sh -c '{
    find /etc/apt /usr/share/keyrings -printf "%p %y %m %l\n" | sort
    find /etc/apt /usr/share/keyrings -type f -exec sha256sum {} + | sort
  } | sha256sum'
}

# The apt configuration still has the digest $1.
apt_configuration_is() {
  if [[ "$(apt_configuration)" != "$1" ]]; then
    echo "/etc/apt or /usr/share/keyrings changed" >&2
    return 1
  fi
}
