#!/bin/sh
# Scenario listed_packages_alpine_3_24 (scenarios.json): spec scenarios "Listed packages are installed"
# and "Caches are removed".
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

check "file is installed" installed file
check "tree is installed" installed tree
check "file runs" file --version
check "tree runs" tree --version
check "the dependency libmagic is installed" installed libmagic
check "file is a line of apk's world" in_world file
check "tree is a line of apk's world" in_world tree
check "/var/cache/apk is empty" cache_empty
check "no directory of the feature is left" no_feature_dir

reportResults
