# shellcheck shell=bash
# Sourced by fail_installation.sh, which runs install.sh itself: a test run puts this checkout's src/godot-dotnet/ in
# _feature/ beside the script (.agents/knowledge/testing.md, Running the installer). The script runs as root, as the
# scenario does, and prepares ${FIXTURE_DIR}: bin/ holds the stubs every run finds first on PATH, fixture_curl.sh as
# curl, which records each request in requests, and an apt-get stub, which records each call in apt-get.calls and
# exits 1. This file holds the run and the assertions on its result; an assertion that fails says what it found and
# shows the run's output.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER
readonly LINK="/usr/local/bin/godot"
readonly INSTALL_ROOT="/opt/godot-dotnet"
readonly MARKER="${INSTALL_ROOT}/.devcontainer-feature-godot-dotnet"

install_version=""
install_status=0
install_output=""

# Runs install.sh with VERSION=$1 and PATH starting with the stub directory $3 (${FIXTURE_DIR}/bin when not given),
# after directory $2 when given; empties the request and call logs first. Keeps the exit status in install_status and
# stdout with stderr in install_output.
run_installer() {
  local stubs="${3:-${FIXTURE_DIR}/bin}"
  install_version="$1"
  : >"${FIXTURE_DIR}/requests"
  : >"${FIXTURE_DIR}/apt-get.calls"
  install_status=0
  install_output="$(env PATH="${2:+$2:}${stubs}:${PATH}" VERSION="$1" bash "${INSTALLER}" 2>&1)" \
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
  local error="${install_output##*godot-dotnet: error: }"
  local text
  if [[ "${install_status}" -eq 0 || "${install_output}" != *"godot-dotnet: error: "* ]]; then
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

# Prints what identifies the installation: what /usr/local/bin/godot is (its link target, or its type), the inode,
# type, mode, and owner of /opt/godot-dotnet, and for each entry two levels below it also the modification time, with
# the marker's content. The modification time of /opt/godot-dotnet itself is left out: a run that fails after creating
# and removing a release directory in it changes that time and nothing else.
installation_state() {
  if [[ -L "${LINK}" ]]; then
    printf 'link -> %s\n' "$(readlink "${LINK}")"
  elif [[ -e "${LINK}" ]]; then
    stat --format 'not a link: %i %F %a %U %Y' "${LINK}"
  else
    echo 'link absent'
  fi
  if [[ -e "${INSTALL_ROOT}" || -L "${INSTALL_ROOT}" ]]; then
    find "${INSTALL_ROOT}" -maxdepth 0 -printf '%i %y %m %u %p\n'
    find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 2 -printf '%i %y %m %u %T@ %p\n' | sort
    if [[ -f "${MARKER}" ]]; then printf 'marker: %s\n' "$(cat "${MARKER}")"; fi
  else
    echo 'install root absent'
  fi
}

# The installation is still as installation_state printed it in $1.
installation_is() {
  local actual
  actual="$(installation_state)"
  if [[ "${actual}" != "$1" ]]; then
    printf '  the installation changed from:\n%s\n  to:\n%s\n' "$1" "${actual}"
    show_run
    return 1
  fi
}

# No temporary directory or temporary link of install.sh remains.
no_temp_residue() {
  local path
  for path in "${TMPDIR:-/tmp}"/godot-dotnet-feature.* /usr/local/bin/.godot-dotnet-feature.*; do
    if [[ -e "${path}" || -L "${path}" ]]; then
      printf '  leftover: %s\n' "${path}"
      show_run
      return 1
    fi
  done
}

# No temporary directory or temporary link of install.sh remains, and /opt/godot-dotnet, if it exists, holds no entry
# but the marker and the release directory the link points into.
no_install_residue() {
  local path
  local release=""
  no_temp_residue || return 1
  if [[ ! -d "${INSTALL_ROOT}" || -L "${INSTALL_ROOT}" ]]; then return 0; fi
  if [[ -L "${LINK}" ]]; then release="$(dirname "$(readlink "${LINK}")")"; fi
  for path in "${INSTALL_ROOT}"/* "${INSTALL_ROOT}"/.[!.]*; do
    if [[ (-e "${path}" || -L "${path}") && "${path}" != "${MARKER}" && "${path}" != "${release}" ]]; then
      printf '  leftover: %s\n' "${path}"
      show_run
      return 1
    fi
  done
}

# godot --version exits 0 and prints exactly $1.
godot_reports() {
  local output
  if ! output="$(godot --version)" || [[ "${output}" != "$1" ]]; then
    printf '  godot --version printed "%s", expected "%s"\n' "${output}" "$1"
    show_run
    return 1
  fi
}

# /usr/local/bin/godot is a link to godot in a directory directly under /opt/godot-dotnet other than $1, which no longer
# exists, and /opt/godot-dotnet holds the marker naming tag $2 and that directory alone.
switched_from() {
  local target
  local release
  target="$(readlink "${LINK}")" || return 1
  release="${target%/godot}"
  if [[ ! "${target}" =~ ^/opt/godot-dotnet/[^/]+/godot$ || "${release}" == "$1" || -e "$1" \
    || "$(cat "${MARKER}")" != "$2" ]]; then
    printf '  link target %s, earlier release %s, marker %s\n' "${target}" "$1" "$(cat "${MARKER}" 2>/dev/null)"
    show_run
    return 1
  fi
  no_install_residue
}
