#!/bin/sh
# Scenario test_listed_packages_alpine_3_24 (scenarios.json): spec scenarios "Listed packages are installed"
# and "Caches are removed".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "file is installed" installed file
check "tree is installed" installed tree
check "file, with its dependencies, is installed: it prints its version" file --version
check "tree, with its dependencies, is installed: the package's tree prints its version" tree_package_prints_its_version
check "the dependency libmagic is installed" installed libmagic
check "file is a line of apk's world" in_world file
check "tree is a line of apk's world" in_world tree
check "/var/cache/apk is left as it was, empty" cache_left_empty
check "no temporary directory of the feature is left" no_temporary_dir

reportResults
