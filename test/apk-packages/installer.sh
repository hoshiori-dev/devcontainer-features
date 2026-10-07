# shellcheck shell=sh
# Sourced, after checks.sh, by the apk-packages scenario scripts that run install.sh themselves. A test run puts this
# checkout's src/apk-packages/ in _feature/ beside the scripts (.agents/knowledge/testing.md, Running the installer).
# The scripts run it as root, which every scenario's container runs as, with the options as environment variables, as
# the devcontainer CLI does at image build time, and assert the exit status, the output, and the state of the
# container. This file holds the run and the assertions several of them use; an assertion that fails says what it
# found.

# An absolute path: a script may start the installer from another directory.
INSTALLER="$(cd "$(dirname "$0")" && pwd)/_feature/install.sh"
readonly INSTALLER

install_status=0
install_output=""

# Runs the command given, which runs install.sh, and prints its output. Keeps the exit status in install_status and
# stdout with stderr in install_output.
record_run() {
  install_status=0
  install_output="$("$@" 2>&1)" || install_status=$?
  printf '%s\n' "${install_output}"
}

# Runs install.sh with the environment assignments given (PACKAGES=tree CLEANUP=none), as record_run does.
run_install() {
  record_run env "$@" "${INSTALLER}"
}

# The last run exited with status $1.
exited_with() {
  if [ "${install_status}" -ne "$1" ]; then
    echo "install.sh exited with status ${install_status}, not $1" >&2
    return 1
  fi
}

# The last run exited with a non-zero status.
install_failed() {
  if [ "${install_status}" -eq 0 ]; then
    echo "install.sh exited with status 0" >&2
    return 1
  fi
}

# The last run printed the text $1.
printed() {
  case "${install_output}" in
    *"$1"*) return 0 ;;
  esac
  printf 'the output of install.sh does not contain "%s"\n' "$1" >&2
  return 1
}

# A line of the last run's output matches the extended regular expression $1.
output_matches() {
  grep -Eq -- "$1" <<EOF
${install_output}
EOF
}

not_installed() {
  if apk info -e "$1" >/dev/null 2>&1; then
    echo "$1 is installed" >&2
    return 1
  fi
}

# No line of apk's world is $1.
not_in_world() {
  if grep -Fqx -- "$1" /etc/apk/world; then
    echo "apk's world holds the line $1" >&2
    return 1
  fi
}

# Prints the installed version of the package $1, read from apk's installed database; nothing when it is not there.
installed_version() {
  awk -v package="$1" \
    '$0 == "P:" package { found = 1 } found && /^V:/ { print substr($0, 3); exit }' /lib/apk/db/installed
}

# The package $1 is installed in the version $2.
installed_in_version() {
  installed_in_version_found="$(installed_version "$1")"
  if [ "${installed_in_version_found}" != "$2" ]; then
    echo "$1 is installed in version '${installed_in_version_found}', not '$2'" >&2
    return 1
  fi
}

# Prints the version the image's repositories offer of the package $1, read without leaving an index in the image;
# nothing when they offer none.
offered_version() {
  apk --no-cache search -x "$1" 2>/dev/null | sed -n "s/^$1-\([0-9]\)/\1/p" | head -n 1
}

# Prints a digest of apk's world, its installed database, the names in /var/cache/apk, and the feature's temporary
# directories: the same digest before and after means nothing was installed, removed, recorded, fetched, or left
# behind.
apk_state() {
  {
    cat /etc/apk/world /lib/apk/db/installed
    ls -A /var/cache/apk
    ls -d /tmp/apk-packages.* 2>/dev/null || true
  } | sha256sum
}

# The state apk_state prints still has the digest $1.
apk_state_is() {
  if [ "$(apk_state)" != "$1" ]; then
    echo "apk's world, its installed database, or a cache changed" >&2
    return 1
  fi
}

# Prints a digest of every path under /etc/apk except the world: names, types, modes, owners, link targets, and the
# content of every file.
apk_configuration() {
  {
    find /etc/apk -mindepth 1 ! -path /etc/apk/world -exec stat -c '%n %F %a %u:%g %N' {} + | sort
    find /etc/apk -type f ! -path /etc/apk/world -exec sha256sum {} + | sort
  } | sha256sum
}

# The configuration apk_configuration prints still has the digest $1.
apk_configuration_is() {
  if [ "$(apk_configuration)" != "$1" ]; then
    echo "a path under /etc/apk other than the world changed" >&2
    return 1
  fi
}
