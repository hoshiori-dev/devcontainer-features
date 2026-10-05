#!/bin/sh
# Install-twice test: apk-packages is installed once with a non-default `packages` from its
# proposals, then once with the defaults. Option values arrive as PACKAGES and PACKAGES__DEFAULT.
# Scenarios "Listed packages are installed" (with the proposals list) and "Caches are removed".
# POSIX sh with its own check and reportResults: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

failed=0

check() {
  label=$1
  shift
  printf '\nTesting: %s\n' "$label"
  if "$@"; then
    echo "Passed: $label"
  else
    echo "FAILED: $label" >&2
    failed=$((failed + 1))
  fi
}

reportResults() {
  if [ "$failed" -ne 0 ]; then
    printf '\n%s check(s) failed\n' "$failed" >&2
    exit 1
  fi
  printf '\nAll checks passed\n'
}

installed() {
  apk info -e "$1" >/dev/null 2>&1
}

in_world() {
  grep -Fqx -- "$1" /etc/apk/world
}

cache_empty() {
  [ -z "$(ls -A /var/cache/apk)" ]
}

no_feature_dir() {
  for dir in "${TMPDIR:-/tmp}"/apk-packages.*; do
    [ ! -e "$dir" ] || return 1
  done
}

PACKAGES="${PACKAGES:-}"

check "the first install had a non-empty list" test -n "$(printf '%s' "$PACKAGES" | tr -d ' ,')"
rest="$PACKAGES,"
while [ -n "$rest" ]; do
  entry=${rest%%,*}
  rest=${rest#*,}
  entry=$(printf '%s' "$entry" | tr -d '[:space:]')
  [ -n "$entry" ] || continue
  check "$entry from the first install is installed" installed "$entry"
  check "$entry is a line of apk's world" in_world "$entry"
done
check "/var/cache/apk is empty" cache_empty
check "no directory of the feature is left" no_feature_dir

reportResults
