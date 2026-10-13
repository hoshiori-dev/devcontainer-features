#!/usr/bin/env bash
# Scenario test_repository_selection_0 (scenarios.json): this script runs install.sh several times in one container
# with enableRepositories and disableRepositories naming repositories the image ships. Spec scenarios "Image repository
# set is inherited", "Disabled repository is enabled for the invocation", "Enabled repository is left out for the
# invocation", "Both lists apply together", "Repository already in the requested state", "Refresh policy and timeout
# cover a temporarily enabled repository", "Cache-only installation needs the metadata of a temporarily enabled
# repository", "Cache-only installation does not need a repository that is left out", "Cleanup covers a temporarily
# enabled repository", "Package-file cleanup covers a temporarily enabled repository", "Spaces and empty items in a
# repository list are ignored", "Repository selection leaves the configuration unchanged", "Repository selection does
# not carry over", and "Same repository and solver controls on the second install".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# A repository the image configures and leaves disabled, and a package that only it offers.
readonly DISABLED_REPOSITORY="fedora-debuginfo"
readonly ONLY_DISABLED_PACKAGE="bc-debuginfo"
# A repository the image enables, and a package that only it offers.
readonly ENABLED_REPOSITORY="fedora-cisco-openh264"
readonly ONLY_ENABLED_PACKAGE="openh264"

# dnf prints one of these texts when it fetches repository metadata or a package.
attempted_no_download() {
  if output_matches 'Downloading|kB/s|KiB/s|MiB/s'; then
    echo "dnf tried to download" >&2
    return 1
  fi
}

# The install call of the last recorded run names --enablerepo=$1 exactly once.
enables_once() {
  local calls
  calls="$(install_calls)" || return
  [[ "$(grep --only-matching --fixed-strings -e "[--enablerepo=$1]" <<<"${calls}" | wc -l)" -eq 1 ]]
}

# In the install call of the last recorded run, --disablerepo=$1 precedes --enablerepo=$2.
disables_before_enabling() {
  local calls
  calls="$(install_calls)" || return
  [[ "${calls}" == *"[--disablerepo=$1]"*"[--enablerepo=$2]"* ]]
}

record_dnf_calls
configuration_before="$(dnf_configuration)"
keys_before="$(rpm_keys)"
states_before="$(repository_states)"
check "premise: the image leaves ${DISABLED_REPOSITORY} disabled" \
  grep --line-regexp --quiet "${DISABLED_REPOSITORY} disabled" <<<"${states_before}"
check "premise: the image enables ${ENABLED_REPOSITORY}" \
  grep --line-regexp --quiet "${ENABLED_REPOSITORY} enabled" <<<"${states_before}"

# Without the options the image's set applies, which does not offer the package of the disabled repository.
run_recorded_install PACKAGES="${ONLY_DISABLED_PACKAGE}" CLEANUP=none
check "with both lists omitted, ${ONLY_DISABLED_PACKAGE}, which only ${DISABLED_REPOSITORY} offers, is not found" failed
check "with both lists omitted, no repository selection is passed" install_call_lacks 'repo'
check "premise: the failed run left the metadata of the image's enabled repositories" has_metadata
check "premise: the cache holds no metadata of ${DISABLED_REPOSITORY}" no_metadata_of "${DISABLED_REPOSITORY}"

run_install PACKAGES="${ONLY_DISABLED_PACKAGE}" ENABLEREPOSITORIES="${DISABLED_REPOSITORY}" REFRESHPOLICY=never \
  CLEANUP=none
check "refreshPolicy=never fails when the temporarily enabled ${DISABLED_REPOSITORY} has no cached metadata" failed
check "refreshPolicy=never attempts no download for ${DISABLED_REPOSITORY}" attempted_no_download
check "refreshPolicy=never fetched no metadata of ${DISABLED_REPOSITORY}" no_metadata_of "${DISABLED_REPOSITORY}"
check "refreshPolicy=never did not install ${ONLY_DISABLED_PACKAGE}" not_installed "${ONLY_DISABLED_PACKAGE}"

# The list holds spaces, an empty item, and the identifier twice.
run_recorded_install PACKAGES="${ONLY_DISABLED_PACKAGE}" \
  ENABLEREPOSITORIES=" ${DISABLED_REPOSITORY} ,, ${DISABLED_REPOSITORY}" CLEANUP=packages
check "enableRepositories=${DISABLED_REPOSITORY} exits with status 0" exited_with 0
check "${ONLY_DISABLED_PACKAGE} is installed from the temporarily enabled ${DISABLED_REPOSITORY}" \
  installed "${ONLY_DISABLED_PACKAGE}"
check "spaces, an empty item, and a repeated identifier count as the identifier once" \
  enables_once "${DISABLED_REPOSITORY}"
check "afterwards ${DISABLED_REPOSITORY} is still disabled in the image" repository_states_are "${states_before}"
check "the repository files are unchanged" dnf_configuration_is "${configuration_before}"
check "premise: cleanup=packages kept the metadata of ${DISABLED_REPOSITORY}" has_metadata_of "${DISABLED_REPOSITORY}"
check "cleanup=packages leaves no downloaded package file of ${DISABLED_REPOSITORY}" no_package_files

run_install PACKAGES="${ONLY_ENABLED_PACKAGE}" DISABLEREPOSITORIES="${ENABLED_REPOSITORY}" CLEANUP=none
check "disableRepositories=${ENABLED_REPOSITORY} fails for ${ONLY_ENABLED_PACKAGE}, which only it offers" failed
check "${ONLY_ENABLED_PACKAGE} is not installed" not_installed "${ONLY_ENABLED_PACKAGE}"
check "afterwards ${ENABLED_REPOSITORY} is still enabled in the image" repository_states_are "${states_before}"

# A second installation with default controls starts from the image's set.
run_recorded_install PACKAGES=tree
check "a later run with default controls succeeds" exited_with 0
check "the later run passes no repository selection" install_call_lacks 'repo'
check "tree is installed from the image's enabled repositories" installed tree
check "${ONLY_DISABLED_PACKAGE}, installed from ${DISABLED_REPOSITORY} before, stays installed" \
  installed "${ONLY_DISABLED_PACKAGE}"

dnf remove --assumeyes "${ONLY_DISABLED_PACKAGE}"
run_recorded_install PACKAGES="${ONLY_DISABLED_PACKAGE}" ENABLEREPOSITORIES="${DISABLED_REPOSITORY}" \
  DISABLEREPOSITORIES="${ENABLED_REPOSITORY}" REFRESHPOLICY=always NETWORKTIMEOUT=30 CLEANUP=all
check "both lists together exit with status 0" exited_with 0
check "${ONLY_DISABLED_PACKAGE} is installed without ${ENABLED_REPOSITORY} and with ${DISABLED_REPOSITORY}" \
  installed "${ONLY_DISABLED_PACKAGE}"
check "every disable argument precedes every enable argument" \
  disables_before_enabling "${ENABLED_REPOSITORY}" "${DISABLED_REPOSITORY}"
check "refreshPolicy=always reaches the call that enables ${DISABLED_REPOSITORY}" install_call_has "--refresh"
check "networkTimeout=30 covers every repository of the call that enables ${DISABLED_REPOSITORY}" \
  install_call_has "--setopt=*.timeout=30"
check "cleanup=all leaves no metadata, also none of ${DISABLED_REPOSITORY}" no_metadata
check "cleanup=all leaves no downloaded package file" no_package_files
check "with both lists the repository files, the dnf configuration, and the key files are unchanged" \
  dnf_configuration_is "${configuration_before}"
check "with both lists the keys in the RPM keyring are unchanged" rpm_keys_are "${keys_before}"
check "with both lists the image enables the same repositories as before" repository_states_are "${states_before}"

# The same list and controls a second time.
for run in first second; do
  run_install PACKAGES="${ONLY_DISABLED_PACKAGE}" ENABLEREPOSITORIES="${DISABLED_REPOSITORY}" \
    DISABLEREPOSITORIES="${ENABLED_REPOSITORY}" BEST=false PARALLELDOWNLOADS=2
  check "the ${run} of two runs with the same list and repository and solver controls succeeds" exited_with 0
done
check "${ONLY_DISABLED_PACKAGE} is installed after both runs" installed "${ONLY_DISABLED_PACKAGE}"
check "after both runs the repository files and the dnf configuration are unchanged" \
  dnf_configuration_is "${configuration_before}"

# Each identifier names a repository that is already in the requested state.
run_install PACKAGES=time ENABLEREPOSITORIES="${ENABLED_REPOSITORY}" DISABLEREPOSITORIES="${DISABLED_REPOSITORY}"
check "enabling the enabled ${ENABLED_REPOSITORY} and disabling the disabled ${DISABLED_REPOSITORY} succeeds" \
  exited_with 0
check "time is installed as without those identifiers" installed time

# The cache gets the metadata of every enabled repository but one, and the package file of ed.
dnf install --assumeyes --downloadonly --setopt=install_weak_deps=False "--disablerepo=${ENABLED_REPOSITORY}" ed
check "premise: the cache holds no metadata of the enabled ${ENABLED_REPOSITORY}" \
  no_metadata_of "${ENABLED_REPOSITORY}"
run_install PACKAGES=ed REFRESHPOLICY=never CLEANUP=none
check "premise: refreshPolicy=never fails while ${ENABLED_REPOSITORY} is enabled without cached metadata" failed
run_install PACKAGES=ed REFRESHPOLICY=never DISABLEREPOSITORIES="${ENABLED_REPOSITORY}" CLEANUP=none
check "refreshPolicy=never succeeds when disableRepositories leaves ${ENABLED_REPOSITORY} out" exited_with 0
check "ed is installed from the remaining repositories" installed ed

reportResults
