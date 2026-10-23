# shellcheck shell=sh
# Sourced by the act test scripts. A POSIX stand-in for dev-container-features-test-lib: that library uses bash
# arrays, which BusyBox ash cannot parse, and alpine:3.24 ships no bash. check and reportResults keep the library's
# names and interface, so an act test reads like a test that sources the library. The rest are the assertions more
# than one test script uses, and the helpers they call.

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
    https://github.com/nektos/act/releases/latest)" || return 1
  if [ -z "${latest_release_location}" ]; then
    echo 'the latest-release link did not redirect to a release' >&2
    return 1
  fi
  latest_release_tag="${latest_release_location%%[?#]*}"
  latest_release_tag="${latest_release_tag%/}"
  latest_release_tag="${latest_release_tag##*/}"
  printf '%s\n' "${latest_release_tag#v}"
}

# `act --version` exits 0 and prints exactly "act version $1".
act_reports_version() {
  act_reports_version_output="$(act --version)" || return 1
  printf "  got '%s', expected 'act version %s'\n" "${act_reports_version_output}" "$1"
  [ "${act_reports_version_output}" = "act version $1" ]
}

# `command -v act` names /usr/local/bin/act, or the same file through a directory symlink: on fedora:44,
# /usr/local/sbin links to bin and comes first on PATH, so it prints /usr/local/sbin/act.
act_resolves_to_usr_local_bin() {
  act_resolves_found="$(command -v act)" || return 1
  printf '  command -v act: %s\n' "${act_resolves_found}"
  act_resolves_dir="$(cd -P "${act_resolves_found%/*}" && pwd)" || return 1
  [ "${act_resolves_dir}/${act_resolves_found##*/}" = "/usr/local/bin/act" ]
}

# Neither the remote user's nor root's home holds act's configuration or cache locations.
no_act_files_in_homes() {
  for no_act_files_home in "${HOME}" /root; do
    for no_act_files_path in .actrc .config/act .cache/act; do
      if as_root test -e "${no_act_files_home}/${no_act_files_path}"; then
        printf '  found: %s/%s\n' "${no_act_files_home}" "${no_act_files_path}"
        return 1
      fi
    done
  done
}

# The file at $1 holds exactly the four lines act's first-run prompt writes for the images tagged $2 ("act" for
# medium, "full" for large).
config_holds_lines() {
  config_holds_expected="$(printf -- '-P ubuntu-%s=catthehacker/ubuntu:'"$2"'-%s\n' \
    latest latest 22.04 22.04 20.04 20.04 18.04 18.04)"
  config_holds_actual="$(cat "$1")" || return 1
  if [ "${config_holds_actual}" != "${config_holds_expected}" ]; then
    printf '  got:\n%s\n  expected:\n%s\n' "${config_holds_actual}" "${config_holds_expected}"
    return 1
  fi
  # $(...) drops trailing newlines, so the byte count also proves each line, the last included, ends with one.
  config_holds_bytes="$(wc -c <"$1")" || return 1
  [ "${config_holds_bytes}" -eq "$((${#config_holds_expected} + 1))" ]
}

# Creates a directory holding one workflow whose job "hello" runs `echo` on ubuntu-latest, and prints its path.
make_workflow_dir() {
  make_workflow_dir_path="$(mktemp -d)" || return 1
  mkdir -p "${make_workflow_dir_path}/.github/workflows"
  cat >"${make_workflow_dir_path}/.github/workflows/hello.yml" <<'WORKFLOW'
on: push
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - run: echo hello
WORKFLOW
  printf '%s\n' "${make_workflow_dir_path}"
}

# No temporary directory, staged binary, or staged configuration file of install.sh remains.
no_install_leftovers() {
  for no_install_leftovers_path in \
    /tmp/act-feature.* "${TMPDIR:-/tmp}"/act-feature.* /usr/local/bin/.act-feature.* \
    "${HOME}"/.config/act/.actrc-feature.* /root/.config/act/.actrc-feature.*; do
    if as_root test -e "${no_install_leftovers_path}"; then
      printf '  leftover: %s\n' "${no_install_leftovers_path}"
      return 1
    fi
  done
}
