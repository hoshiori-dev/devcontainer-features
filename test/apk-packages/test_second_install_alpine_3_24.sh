#!/bin/sh
# Scenario test_second_install_alpine_3_24 (scenarios.json): this script installs one list and then another in the same
# container, on an image whose configured cache /etc/apk/cache holds a file. Spec scenarios "Caches are removed" and
# "Existing image caches are preserved" (the configured cache), "Apk configuration is unchanged", "Same list on the
# second install", "Different list on the second install", and "Later entry replaces the earlier constraint".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# Prints the names in the image's cache /var/cache/apk and a digest of each file there.
image_cache() {
  (cd /var/cache/apk && ls -A && sha256sum ./*)
}

image_cache_is() {
  if [ "$(image_cache)" != "$1" ]; then
    echo "/var/cache/apk changed" >&2
    return 1
  fi
}

# No package index or package file is left on the image's file system, in a cache or elsewhere.
no_index_or_package_file_remains() {
  no_index_or_package_file_remains_found="$(find / -xdev \( -name 'APKINDEX*' -o -name '*.apk' \) 2>/dev/null || true)"
  if [ -n "${no_index_or_package_file_remains_found}" ]; then
    echo "index or package files remain: ${no_index_or_package_file_remains_found}" >&2
    return 1
  fi
}

ln -s /var/cache/apk /etc/apk/cache
echo kept >/var/cache/apk/kept
cache_before="$(image_cache)"
configuration_before="$(apk_configuration)"

run_install PACKAGES=file,tree
check "a first run with the list file,tree succeeds" exited_with 0
check "file is installed" installed file
check "tree is installed" installed tree
check "the configured cache /var/cache/apk holds the same files as before" image_cache_is "${cache_before}"
check "no temporary directory of the feature is left" no_temporary_dir
check "no package index or package file remains in the image" no_index_or_package_file_remains
check "every path under /etc/apk other than the world is unchanged" apk_configuration_is "${configuration_before}"

run_install PACKAGES=file,tree
check "a second run with the same list succeeds" exited_with 0
check "file is still installed" installed file
check "tree is still installed" installed tree

# jq and pv stand for the two different lists: file and tree are installed by now.
run_install PACKAGES=jq
check "a run with the list jq succeeds" exited_with 0
run_install PACKAGES=pv
check "a later run with the different list pv succeeds" exited_with 0
check "jq, which the earlier list named, is installed" installed jq
check "pv, which the later list named, is installed" installed pv
check "jq is a line of apk's world" in_world jq
check "pv is a line of apk's world" in_world pv

# The version the repositories offer when the test runs: a fixed version would go stale with the next release.
less_version="$(offered_version less)"
check "premise: the repositories offer less" test -n "${less_version}"
run_install PACKAGES="less=${less_version}"
check "a run with less=${less_version} succeeds" exited_with 0
check "less=${less_version} is a line of apk's world" in_world "less=${less_version}"
run_install PACKAGES=less
check "a later run with less, without a constraint, succeeds" exited_with 0
check "less is a line of apk's world" in_world less
check "less=${less_version} is no longer a line of apk's world" not_in_world "less=${less_version}"
check "less stays at ${less_version}" installed_in_version less "${less_version}"

reportResults
