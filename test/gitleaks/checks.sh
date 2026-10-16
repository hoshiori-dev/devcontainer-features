# shellcheck shell=sh
# Sourced by the gitleaks test scripts. A POSIX stand-in for dev-container-features-test-lib: that library uses
# bash arrays, which BusyBox ash cannot parse, and alpine:3.24 ships no bash. check and reportResults keep the
# library's names and interface, so a gitleaks test reads like a test that sources the library. The rest are the
# assertions more than one test script uses, and the helpers they call.

failed=""

# Runs a command and records the label when it fails: check <label> <command> [args...].
check() {
  check_label="$1"
  shift
  printf "Testing '%s'\n" "${check_label}"
  if "$@"; then
    printf "Passed '%s'\n" "${check_label}"
  else
    printf "FAILED '%s'\n" "${check_label}" >&2
    failed="${failed}
  - ${check_label}"
  fi
}

# Lists the failed labels and exits 1, or exits 0 when every check passed. The camelCase name is the library's.
reportResults() {
  if [ -n "${failed}" ]; then
    printf 'Failed tests:%s\n' "${failed}" >&2
    exit 1
  fi
  echo "Test Passed!"
  exit 0
}

# Runs a command as root: directly when already root, else through passwordless sudo.
as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# Prints the version the latest-release link names when called, read as install.sh reads it, without following the
# redirect, and without the tag's leading "v"; a release between build and test fails the comparison once.
latest_release() {
  latest_release_location="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 \
    --head --output /dev/null --write-out '%{redirect_url}' \
    https://github.com/gitleaks/gitleaks/releases/latest)" || return 1
  if [ -z "${latest_release_location}" ]; then
    echo 'the latest-release link did not redirect to a release' >&2
    return 1
  fi
  latest_release_tag="${latest_release_location%%[?#]*}"
  latest_release_tag="${latest_release_tag%/}"
  latest_release_tag="${latest_release_tag##*/}"
  printf '%s\n' "${latest_release_tag#v}"
}

# `gitleaks version` exits 0 and prints exactly version $1.
gitleaks_reports_version() {
  gitleaks_reports_version_output="$(gitleaks version)" || return 1
  printf "  got '%s', expected '%s'\n" "${gitleaks_reports_version_output}" "$1"
  [ "${gitleaks_reports_version_output}" = "$1" ]
}

# `command -v gitleaks` names /usr/local/bin/gitleaks, or the same file through a directory symlink: on
# fedora:44, /usr/local/sbin links to bin and comes first on PATH, so it prints /usr/local/sbin/gitleaks.
gitleaks_resolves_to_usr_local_bin() {
  gitleaks_resolves_found="$(command -v gitleaks)" || return 1
  printf '  command -v gitleaks: %s\n' "${gitleaks_resolves_found}"
  gitleaks_resolves_dir="$(cd -P "${gitleaks_resolves_found%/*}" && pwd)" || return 1
  [ "${gitleaks_resolves_dir}/${gitleaks_resolves_found##*/}" = "/usr/local/bin/gitleaks" ]
}

# Neither the remote user's nor root's home holds a file or directory whose name contains "gitleaks".
no_gitleaks_files_in_homes() {
  no_gitleaks_files_found="$(as_root find "${HOME}" /root -name '*gitleaks*' 2>/dev/null)" || return 1
  if [ -n "${no_gitleaks_files_found}" ]; then
    printf '  found:\n%s\n' "${no_gitleaks_files_found}"
    return 1
  fi
}

# No temporary directory or staged binary of install.sh remains.
no_install_leftovers() {
  for no_install_leftovers_path in \
    /tmp/gitleaks-feature.* "${TMPDIR:-/tmp}"/gitleaks-feature.* /usr/local/bin/.gitleaks-feature.*; do
    if [ -e "${no_install_leftovers_path}" ]; then
      printf '  leftover: %s\n' "${no_install_leftovers_path}"
      return 1
    fi
  done
}
