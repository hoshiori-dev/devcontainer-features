# shellcheck shell=bash
# Sourced by fail_installation.sh, which runs install.sh itself: a test run puts this checkout's src/godot/ in
# _feature/ beside the script (.agents/knowledge/testing.md, Running the installer). The script runs as root, as the
# scenario does, and prepares ${FIXTURE_DIR}: bin/ holds the stubs every run finds first on PATH, fixture_curl.sh as
# curl, which records each request in requests, and an apt-get stub, which records each call in apt-get.calls and
# exits 1; godot.real holds the godot the CLI installed. This file holds the run and the assertions on its result; an
# assertion that fails says what it found and shows the run's output.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
readonly TARGET="/usr/local/bin/godot"

install_version=""
install_status=0
install_output=""

# Runs install.sh with VERSION=$1 and PATH starting with ${FIXTURE_DIR}/bin, after directory $2 when given; empties the
# request and call logs first. Keeps the exit status in install_status and stdout with stderr in install_output.
run_installer() {
  install_version="$1"
  : >"${FIXTURE_DIR}/requests"
  : >"${FIXTURE_DIR}/apt-get.calls"
  install_status=0
  install_output="$(env PATH="${2:+$2:}${FIXTURE_DIR}/bin:${PATH}" VERSION="$1" bash "${INSTALLER}" 2>&1)" \
    || install_status=$?
}

# Prints the last run's version, exit status, and output.
show_run() {
  printf '  install.sh with VERSION=%s exited with status %s:\n%s\n' "${install_version}" "${install_status}" \
    "${install_output}"
}

# The last run exited 0.
succeeded() {
  if [[ "${install_status}" -ne 0 ]]; then
    show_run
    return 1
  fi
}

# The last run exited non-zero, and its error message contains every text given.
failed_with() {
  local error="${install_output##*godot: error: }"
  local text
  if [[ "${install_status}" -eq 0 || "${install_output}" != *"godot: error: "* ]]; then
    show_run
    return 1
  fi
  for text in "$@"; do
    if [[ "${error}" != *"${text}"* ]]; then
      printf '  the error message does not contain "%s"\n' "${text}"
      show_run
      return 1
    fi
  done
}

# The last run made no request through curl.
requested_nothing() {
  if [[ -s "${FIXTURE_DIR}/requests" ]]; then
    printf '  requested:\n'
    cat "${FIXTURE_DIR}/requests"
    show_run
    return 1
  fi
}

# The last run requested the latest-release link and nothing else, so it downloaded no archive.
requested_only_latest() {
  local requests
  requests="$(cat "${FIXTURE_DIR}/requests")"
  if [[ "${requests}" != "https://github.com/godotengine/godot/releases/latest" ]]; then
    printf '  requested:\n%s\n' "${requests}"
    show_run
    return 1
  fi
}

# The last run made no request through curl, called apt-get not once, and left libfontconfig.so.1 unknown to the
# dynamic linker, as fail_installation.sh prepares it for the runs that must fail before any change.
nothing_downloaded_or_installed() {
  local linker_cache
  linker_cache="$(ldconfig -p)"
  if [[ -s "${FIXTURE_DIR}/requests" || -s "${FIXTURE_DIR}/apt-get.calls" \
    || "${linker_cache}" == *libfontconfig.so.1* ]]; then
    printf '  requested:\n'
    cat "${FIXTURE_DIR}/requests"
    printf '  apt-get calls:\n'
    cat "${FIXTURE_DIR}/apt-get.calls"
    printf '  libfontconfig.so.1 in ldconfig -p:\n'
    grep libfontconfig.so.1 <<<"${linker_cache}"
    show_run
    return 1
  fi
}

# /usr/local/bin/godot is still the godot the CLI installed: the same SHA-512 digest as godot.real.
godot_unchanged() {
  local expected
  local actual
  expected="$(sha512sum <"${FIXTURE_DIR}/godot.real")"
  actual="$(sha512sum <"${TARGET}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '  %s has SHA-512 %s, not %s\n' "${TARGET}" "${actual%% *}" "${expected%% *}"
    show_run
    return 1
  fi
}

# Prints the inode and modification time of /usr/local/bin/godot.
target_identity() {
  stat --format '%i %y' "${TARGET}"
}

# /usr/local/bin/godot still has the inode and modification time $1, as target_identity printed them.
target_identity_is() {
  local actual
  actual="$(target_identity)"
  if [[ "${actual}" != "$1" ]]; then
    printf '  %s has inode and modification time %s, not %s\n' "${TARGET}" "${actual}" "$1"
    show_run
    return 1
  fi
}

# No temporary directory or staged executable of install.sh remains.
no_install_residue() {
  local path
  for path in "${TMPDIR:-/tmp}"/godot-feature.* /usr/local/bin/.godot-feature.*; do
    if [[ -e "${path}" ]]; then
      printf '  leftover: %s\n' "${path}"
      show_run
      return 1
    fi
  done
}
