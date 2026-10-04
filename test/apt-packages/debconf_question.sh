#!/usr/bin/env bash
# Scenario debconf_question (scenarios.json): spec scenarios "Package that asks a question installs unattended"
# and "Caches are removed". keyboard-configuration asks for the keyboard layout; the build has no
# terminal, so the feature must take the default answer, the US layout.
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

default_layout() {
  grep -qx 'XKBLAYOUT="us"' /etc/default/keyboard
}

check "keyboard-configuration is installed and configured" installed keyboard-configuration
check "the layout question took its default answer" default_layout
check "no downloaded package file is left" no_package_files
check "no package index file is left" no_index_files

reportResults
