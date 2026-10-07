#!/usr/bin/env bash
# Scenario test_entry_forms_ubuntu (scenarios.json): this script runs install.sh in a container it has prepared, with
# lists that install. Spec scenarios "Suggested packages are left out when the image enables them" (requirement
# "Install the listed packages"), "Apt configuration is unchanged", "Package name ending in plus is installed", and
# "Virtual package with one provider installs".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly SUGGESTS_CONFIGURATION="/etc/apt/apt.conf.d/99-test-suggests"

# readline-doc, which a dependency of bc suggests, is installed or not ("yes" or "no" in $1) as before the run.
readline_doc_installed_is() {
  local now=no
  if [[ "$(dpkg-query -W -f='${Status}' readline-doc 2>/dev/null)" == "install ok installed" ]]; then now=yes; fi
  [[ "${now}" == "$1" ]]
}

suggested_before=no
if [[ "$(dpkg-query -W -f='${Status}' readline-doc 2>/dev/null)" == "install ok installed" ]]; then
  suggested_before=yes
fi
printf 'APT::Install-Suggests "true";\n' | as_root tee "${SUGGESTS_CONFIGURATION}" >/dev/null
run_install PACKAGES=bc
check "bc installs in an image that enables suggested packages" exited_with 0
check "bc is installed" installed bc
check "the suggested readline-doc is not installed by the run" readline_doc_installed_is "${suggested_before}"
as_root rm "${SUGGESTS_CONFIGURATION}"

configuration_before="$(apt_configuration)"
run_install PACKAGES="file,dc"
check "file,dc installs" exited_with 0
check "file is installed" installed file
check "dc is installed" installed dc
check "the repository lists, the trusted keys, and the files under /etc/apt are as before the run" \
  apt_configuration_is "${configuration_before}"

run_install PACKAGES="g++"
check "g++ (a package name ending in plus) installs" exited_with 0
check "g++ is installed" installed g++

run_install PACKAGES=libz-dev
check "libz-dev (a virtual package with one provider) installs" exited_with 0
check "its provider zlib1g-dev is installed" installed zlib1g-dev

reportResults
