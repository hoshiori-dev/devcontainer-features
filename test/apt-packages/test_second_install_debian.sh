#!/usr/bin/env bash
# Scenario test_second_install_debian (scenarios.json): this script runs install.sh several times in one container and
# asserts what each later run leaves. Spec scenarios "Same list on the second install", "Listed package already
# installed at its candidate version", "Different list on the second install", "Conflicting package fails without
# removal", "Conflicting list on the second install", "Pinned version is installed", and "Pin below the installed
# version on the second install".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints "<package> <older version> <candidate version>" for a package that is not installed, that the repositories
# offer in two versions, and whose older version installs (simulated). Chosen when the test runs, so that no fixed
# version goes stale. Needs a package index.
two_version_package() {
  local preferred="unzip rsync less nano zip xxd patch sqlite3 libxml2-utils wget curl openssh-client tzdata"
  local generic
  generic="$(/usr/lib/apt/apt-helper cat-file /var/lib/apt/lists/*-security_*_Packages* \
    /var/lib/apt/lists/*-updates_*_Packages* 2>/dev/null | sed -n 's/^Package: //p' | head -n 300)" || generic=""
  local package candidate version
  for package in ${preferred} ${generic}; do
    if [[ "$(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null)" == "install ok installed" ]]; then continue; fi
    candidate="$(apt-cache policy "${package}" | sed -n 's/^  Candidate: //p')"
    if [[ -z "${candidate}" || "${candidate}" == "(none)" ]]; then continue; fi
    while read -r version; do
      if ! dpkg --compare-versions "${version}" lt "${candidate}"; then continue; fi
      if apt-get -s -qq install --no-install-recommends -o APT::Cmd::Pattern-Only=true -- "${package}=${version}" \
        >/dev/null 2>&1; then
        echo "${package} ${version} ${candidate}"
        return 0
      fi
    done < <(apt-cache madison "${package}" | grep ' Packages$' | awk -F'|' '{gsub(/ /, "", $2); print $2}' | sort -u)
  done
  echo "no package that is not installed is offered in two versions whose older one installs" >&2
  return 1
}

version_of() {
  dpkg-query -W -f='${Version}' "$1"
}

has_version() {
  if [[ "$(version_of "$1")" != "$2" ]]; then
    echo "$1 is at $(version_of "$1"), not $2" >&2
    return 1
  fi
}

# The index the script reads candidates from goes again, so that every run of install.sh starts without one.
remove_index() {
  as_root sh -c 'rm -rf /var/lib/apt/lists/*'
}

run_install PACKAGES=bc
check "the first installation of bc succeeds" exited_with 0
check "bc is installed" installed bc
first_version="$(version_of bc)"
run_install PACKAGES=bc
check "the second installation of the same list succeeds" exited_with 0
check "bc, already at its candidate version, is left as it was" has_version bc "${first_version}"
as_root apt-get update -qq --error-on=any
check "premise: the installed bc is the candidate version" \
  has_version bc "$(apt-cache policy bc | sed -n 's/^  Candidate: //p')"
remove_index

run_install PACKAGES=file
check "a second installation with a different list succeeds" exited_with 0
check "bc, which the earlier list named, is still installed" installed bc
check "file, which the later list named, is installed" installed file

run_install PACKAGES=chrony
check "the installation of chrony succeeds" exited_with 0
status_before="$(dpkg_status)"
run_install PACKAGES=openntpd
check "a later list naming openntpd, which conflicts with chrony, fails" failed
check "chrony stays installed" installed chrony
check "openntpd is not installed" not_installed openntpd
check "the installed packages are unchanged" dpkg_status_is "${status_before}"
remove_index

as_root apt-get update -qq --error-on=any
selection="$(two_version_package)"
read -r package older candidate <<<"${selection}"
remove_index
run_install PACKAGES="${package}=${older}"
check "${package}=${older} (a pinned version) installs" exited_with 0
check "${package} is installed at the pinned version ${older}" has_version "${package}" "${older}"
run_install PACKAGES="${package}"
check "a later list naming ${package} without a version succeeds" exited_with 0
check "premise: ${package} is now at its candidate version ${candidate}" has_version "${package}" "${candidate}"
run_install PACKAGES="${package}=${older}"
check "a later list pinning ${package} below the installed version fails" failed
check "${package} stays at ${candidate}" has_version "${package}" "${candidate}"

reportResults
