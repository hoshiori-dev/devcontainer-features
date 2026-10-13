#!/usr/bin/env bash
# Scenario fail_libzypp_without_dropins (scenarios.json): the scenario's Dockerfile is an image outside the
# compatibility list whose libzypp does not provide the RPM capability libzypp(econf), the container has no network,
# and the feature is installed with an empty list. This script runs install.sh with a timeout or retry option and the
# list bc. Spec scenario "Libzypp without additional configuration files fails an explicit override"; and requirement
# "Timeout and retry overrides are temporary" for the three options empty, when the capability is not examined.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

lacks_the_capability() {
  ! rpm -q --whatprovides 'libzypp(econf)' >/dev/null
}

check "premise: no installed package provides libzypp(econf)" lacks_the_capability
database_before="$(rpm_database)"
configuration_before="$(libzypp_configuration)"

# Each entry is "<option> <environment assignment>".
for override in "connectTimeout CONNECTTIMEOUT=30" "transferTimeout TRANSFERTIMEOUT=30" \
  "downloadRetries DOWNLOADRETRIES=2"; do
  option="${override%% *}"
  run_install PACKAGES=bc "${override#* }"
  check "${option} fails with status 1 on a libzypp without libzypp(econf)" exited_with 1
  check "the message of ${option} names the option" printed "${option}"
  check "the message of ${option} names the capability" printed "libzypp(econf)"
  check "${option} refreshes no metadata" did_not_print "refreshing the repository metadata"
done

check "no run downloaded metadata" no_raw_metadata
check "no run changed an installed package" rpm_database_is "${database_before}"
check "no run wrote a configuration file" libzypp_configuration_is "${configuration_before}"

# Without a network the refresh fails; that the run reaches it shows that the capability was not examined.
run_install PACKAGES=bc EXACTNAMES=true LOCKTIMEOUT=5
check "with the three options empty the feature gets as far as the refresh" printed "refreshing the repository metadata"
check "with the three options empty the feature does not name the capability" did_not_print "libzypp(econf)"

reportResults
