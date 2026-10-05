# shellcheck shell=sh
# A POSIX stand-in for dev-container-features-test-lib, which is bash: the same check and reportResults interface, for
# the uv tests that run on alpine:3.24, which ships no bash.

failed=""

# Runs a command and records the label when it fails: check <label> <command> [args...]. Returns 1 after a failure,
# as the library does, so a test under set -e stops at its first failed check.
check() {
  check_label=$1
  shift
  printf "Testing '%s'\n" "${check_label}"
  if "$@"; then
    printf "Passed '%s'\n" "${check_label}"
    return 0
  fi
  printf "FAILED '%s'\n" "${check_label}" >&2
  failed="${failed}
  - ${check_label}"
  return 1
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
