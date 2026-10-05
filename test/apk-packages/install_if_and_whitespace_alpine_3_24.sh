#!/bin/sh
# Scenario install_if_and_whitespace_alpine_3_24 (scenarios.json): spec scenarios "Install-if packages
# follow their conditions", "Spaces and empty entries are ignored", and "Caches are removed". The
# value has spaces, a tab, and an empty entry; jq-doc is installed only through its install-if
# conditions, jq and docs.
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

check "jq is installed" installed jq
check "docs is installed" installed docs
check "jq runs" jq --version
check "jq-doc, whose install-if conditions are met, is installed" installed jq-doc
check "jq is a line of apk's world" in_world jq
check "docs is a line of apk's world" in_world docs
check "jq-doc is not in apk's world" sh -c '! grep -Fqx jq-doc /etc/apk/world'
check "/var/cache/apk is empty" cache_empty
check "no directory of the feature is left" no_feature_dir

reportResults
