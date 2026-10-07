#!/usr/bin/env bash
# Scenario test_second_install_1 (scenarios.json): this script runs install.sh several times in one container and
# asserts what each later run leaves. Spec scenarios "Pin below the installed version on the second install", "Weak
# dependencies are left out", "Optional dependency selection is enabled", and requirement "Installing the feature twice"
# for a later installWeakDeps=false, which uninstalls nothing.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints "<package> <oldest edition>" for the first of a few packages that the repositories offer in more than one
# edition ("<version>-<release>", after "<epoch>:" where the package has one). Chosen when the test runs, so that no
# fixed version goes stale.
two_edition_package() {
  local candidate listing editions count
  for candidate in file bc libfuse3-3 openssl-libs curl-minimal glibc; do
    listing="$(dnf list --showduplicates "${candidate}" 2>/dev/null)" || continue
    editions="$(awk -v prefix="${candidate}." 'index($1, prefix) == 1 { print $2 }' <<<"${listing}" | sort -u -V)"
    count="$(wc -l <<<"${editions}")"
    if [[ "${count}" -gt 1 ]]; then
      echo "${candidate} $(head -n 1 <<<"${editions}")"
      return 0
    fi
  done
  echo "none of the candidate packages is offered in two editions" >&2
  return 1
}

selection="$(two_edition_package)"
read -r package older <<<"${selection}"
run_install PACKAGES="${package}"
check "the installation of ${package} without a version succeeds" exited_with 0
newer="$(version_of "${package}")"
check "premise: ${package} is at ${newer}, above the offered ${older#*:}" test "${newer}" != "${older#*:}"
run_install PACKAGES="${package}-${older}"
check "a later list pinning ${package}-${older}, below the installed version, succeeds" exited_with 0
check "${package} is at the pinned version ${older#*:}" has_version "${package}" "${older#*:}"

# ipcalc recommends geolite2-city in the repositories of every image in the compatibility list, and nothing that is
# installed requires it.
run_install PACKAGES=ipcalc CLEANUP=none
check "ipcalc installs with the default installWeakDeps" exited_with 0
check "the recommended geolite2-city is not installed by default" not_installed geolite2-city
# dnf resolves weak dependencies only for a package it installs, so ipcalc goes before the next run.
dnf remove --assumeyes ipcalc
run_install PACKAGES=ipcalc INSTALLWEAKDEPS=true CLEANUP=none
check "ipcalc installs with installWeakDeps=true on a later run" exited_with 0
check "the recommended geolite2-city is installed with installWeakDeps=true" installed geolite2-city
run_install PACKAGES=ipcalc INSTALLWEAKDEPS=false
check "a later run with installWeakDeps=false succeeds" exited_with 0
check "the later installWeakDeps=false leaves geolite2-city installed" installed geolite2-city

reportResults
