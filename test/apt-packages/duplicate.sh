#!/usr/bin/env bash
# Install-twice test: apt-packages is installed once with a non-default `packages` from its
# proposals, then once with the defaults. Option values arrive as PACKAGES and PACKAGES__DEFAULT.
# Scenarios "Listed packages are installed" (with the proposals list) and "Caches are removed".
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" = "install ok installed" ]
}

no_package_files() {
  [ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]
}

no_index_files() {
  [ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]
}

check "the first install had a non-empty list" test -n "${PACKAGES//[ ,]/}"
IFS=, read -r -a entries <<<"$PACKAGES"
for entry in "${entries[@]}"; do
  entry="${entry//[[:space:]]/}"
  [ -n "$entry" ] || continue
  check "$entry from the first install is installed" installed "$entry"
done
# The second invocation's empty default list is a no-op, so the first cleanup
# policy determines cache state. The control checks cover two non-empty lists.
case ${CLEANUP:-all} in
  all)
    check "package files are cleaned" no_package_files
    check "metadata is cleaned" no_index_files
    ;;
  packages)
    check "package files are cleaned" no_package_files
    check "metadata survives the empty second invocation" bash -c 'find /var/lib/apt/lists -name "*_Packages*" | grep -q .'
    ;;
  none) ;;
esac

reportResults
