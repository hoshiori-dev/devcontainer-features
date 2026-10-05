#!/usr/bin/env bash
# Install-twice test: apt-packages installed twice in one image, first with non-default options, then with the
# defaults. The devcontainer CLI derives the first install's values from devcontainer-feature.json: the second proposal
# of `packages` ("bc,file"), the opposite of each boolean default, and the enum value after each default
# (refreshPolicy=always, cleanup=packages). The second install's default list is empty, so it changes nothing.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

# The images' docker-clean APT hook deletes downloaded package files too, so this check cannot fail on them;
# control_checks.ts proves the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

has_index() {
  [[ -n "$(find /var/lib/apt/lists -name '*_Packages*' -print -quit)" ]]
}

check "bc, which the first installation listed, is installed" installed bc
check "file, which the first installation listed, is installed" installed file
check "package files are removed from the managed cache" no_package_files
# Spec scenario "Empty list ignores installation controls": the second install's default cleanup=all would remove the
# index that the first install's cleanup=packages kept.
check "the second installation's empty list touches no cache: the package index remains" has_index

reportResults
