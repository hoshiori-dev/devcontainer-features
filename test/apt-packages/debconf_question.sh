#!/usr/bin/env bash
# Scenario debconf_question (scenarios.json): spec scenarios "Package that asks a question installs unattended" and
# "Caches are removed". keyboard-configuration asks for the keyboard layout; the build has no terminal, so the package
# is configured with the default answer, the US layout.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

installed() {
  [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]]
}

us_layout() {
  grep -qx 'XKBLAYOUT="us"' /etc/default/keyboard
}

# The image's docker-clean APT hook deletes downloaded package files too, so this check cannot fail on it;
# control_checks.ts proves the cleanup with a relocated archive directory.
no_package_files() {
  [[ -z "$(find /var/cache/apt/archives -name '*.deb' -print -quit)" ]]
}

no_index_files() {
  [[ -z "$(find /var/lib/apt/lists -type f ! -name lock -print -quit)" ]]
}

check "keyboard-configuration is installed" installed keyboard-configuration
check "keyboard-configuration is configured with the default answer, the US layout" us_layout
check "the image holds no downloaded package files" no_package_files
check "the image holds no package index files" no_index_files

reportResults
