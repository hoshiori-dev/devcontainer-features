#!/usr/bin/env bash
# Install-twice test: pacman-packages is installed once with a non-default `packages` from its
# proposals, then once with the defaults. Option values arrive as PACKAGES and PACKAGES__DEFAULT.
# Scenarios "Listed packages are installed" (with the proposals list), "Different list on the second
# install" (the second, default list is empty), and "Caches are removed".
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  pacman -Qq "$1" >/dev/null 2>&1
}

no_package_files() {
  [ -z "$(find /var/cache/pacman/pkg -mindepth 1 -print -quit)" ]
}

no_sync_databases() {
  [ -z "$(find /var/lib/pacman/sync -mindepth 1 -print -quit)" ]
}

check "the first install had a non-empty list" test -n "${PACKAGES//[ ,]/}"
IFS=, read -r -a entries <<<"$PACKAGES"
for entry in "${entries[@]}"; do
  entry="${entry//[[:space:]]/}"
  [ -n "$entry" ] || continue
  check "$entry from the first install is installed" installed "$entry"
done
check "no downloaded package or signature file is left" no_package_files
check "no sync database file is left" no_sync_databases

reportResults
