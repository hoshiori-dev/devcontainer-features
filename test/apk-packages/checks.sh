# shellcheck shell=sh
# Sourced by the apk-packages test scripts: a POSIX stand-in for dev-container-features-test-lib with the same check
# and reportResults interface (that library is bash, and the Alpine images ship none), and the assertions several of
# the scripts use.

failed=0

# Runs a command and counts the label as failed when the command fails: check <label> <command> [args...].
check() {
  check_label="$1"
  shift
  printf '\nTesting: %s\n' "${check_label}"
  if "$@"; then
    printf 'Passed: %s\n' "${check_label}"
  else
    printf 'FAILED: %s\n' "${check_label}" >&2
    failed=$((failed + 1))
  fi
}

# Exits 1 when a check failed, after every check has run. The camelCase name is the library's.
reportResults() {
  if [ "${failed}" -ne 0 ]; then
    printf '\n%s check(s) failed\n' "${failed}" >&2
    exit 1
  fi
  printf '\nAll checks passed\n'
}

installed() {
  apk info -e "$1" >/dev/null 2>&1
}

# $1 is a whole line of apk's world, constraint included.
in_world() {
  grep -Fqx -- "$1" /etc/apk/world
}

# /var/cache/apk, which the supported images ship empty, still holds nothing.
cache_left_empty() {
  cache_left_empty_entries="$(ls -A /var/cache/apk)" || return 1
  [ -z "${cache_left_empty_entries}" ]
}

# No temporary package cache or work directory of install.sh is left.
no_temporary_dir() {
  for no_temporary_dir_path in "${TMPDIR:-/tmp}"/apk-packages.*; do
    [ ! -e "${no_temporary_dir_path}" ] || return 1
  done
}
