# shellcheck shell=sh
# Sourced by the glab test scripts. A POSIX stand-in for dev-container-features-test-lib: that library uses bash
# arrays, which BusyBox ash cannot parse, and alpine:3.24 ships no bash. check and reportResults keep the library's
# names and interface, so a glab test reads like a test that sources the library. The rest are the assertions more
# than one test script uses, and the two helpers they call.

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

# Runs glab without an update check or telemetry, so tests contact no host through glab.
glab_quiet() {
  GLAB_CHECK_UPDATE=false CHECK_UPDATE=false GLAB_SEND_TELEMETRY=false glab "$@"
}

# `glab --version` exits 0 and reports version $1, in either output format glab has used since 1.47.0.
glab_reports_version() {
  glab_reports_version_output="$(glab_quiet --version)" || return 1
  printf "  got '%s', expected version '%s'\n" "${glab_reports_version_output}" "$1"
  case "${glab_reports_version_output}" in
    "glab $1 ("* | "Current glab version: $1" | "Current glab version: $1 ("*) return 0 ;;
  esac
  return 1
}

# `command -v glab` names /usr/local/bin/glab, or the same file through a directory symlink: on fedora:44,
# /usr/local/sbin links to bin and comes first on PATH, so it prints /usr/local/sbin/glab.
glab_resolves_to_usr_local_bin() {
  glab_resolves_to_usr_local_bin_found="$(command -v glab)" || return 1
  printf '  command -v glab: %s\n' "${glab_resolves_to_usr_local_bin_found}"
  glab_resolves_to_usr_local_bin_dir="$(cd -P "${glab_resolves_to_usr_local_bin_found%/*}" && pwd)" || return 1
  [ "${glab_resolves_to_usr_local_bin_dir}/${glab_resolves_to_usr_local_bin_found##*/}" = "/usr/local/bin/glab" ]
}

# No glab configuration directory in the remote user's or root's home.
no_glab_config() {
  [ ! -e "${XDG_CONFIG_HOME:-${HOME}/.config}/glab-cli" ] \
    && [ ! -e "${HOME}/.config/glab-cli" ] \
    && as_root test ! -e /root/.config/glab-cli
}

# No temporary directory or staged binary of install.sh remains.
no_install_leftovers() {
  for no_install_leftovers_path in \
    /tmp/glab-feature.* "${TMPDIR:-/tmp}"/glab-feature.* /usr/local/bin/.glab-feature.*; do
    if [ -e "${no_install_leftovers_path}" ]; then
      printf '  leftover: %s\n' "${no_install_leftovers_path}"
      return 1
    fi
  done
}
