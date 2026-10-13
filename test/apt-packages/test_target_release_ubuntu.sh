#!/usr/bin/env bash
# Scenario test_target_release_ubuntu (scenarios.json): the container has no network; this script publishes releases of
# its own in it (repository.sh) and runs install.sh against them. Every scenario of the spec requirements "Target
# release prefers a configured release", "Target release selects only among configured sources", and "Target release
# ranks with holds and pins as APT does", and the scenarios "Omitted targetRelease", "Configuration selected by the
# environment is honored", and "Later invocation keeps what the earlier one installed".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"
# shellcheck source=/dev/null
source "$(dirname "$0")/repository.sh"

readonly DEFAULT_RELEASE="/etc/apt/apt.conf.d/99-scenario-default-release"
readonly PREFERENCES="/etc/apt/preferences.d/scenario"
readonly SELECTED_CONFIGURATION="/tmp/selected-apt.conf"

# The image's APT configuration names the release $1 as its default release.
image_prefers() {
  printf 'APT::Default-Release "%s";\n' "$1" | as_root tee "${DEFAULT_RELEASE}" >/dev/null
}

# The image pins what the lines $1 and $2 of an APT preferences record name with the priority $3.
image_pins() {
  printf '%s\n' "$1" "$2" "Pin-Priority: $3" | as_root tee "${PREFERENCES}" >/dev/null
}

# The package index holds the package list of every suite given.
index_holds() {
  local suite
  for suite in "$@"; do
    if ! compgen -G "/var/lib/apt/lists/*_dists_${suite}_main_binary-*_Packages*" >/dev/null; then
      echo "the package index holds no package list of ${suite}" >&2
      return 1
    fi
  done
}

# Two suites with distinct suite names, codenames, and versions. Each package of the list is in alpha at 1.0 and in
# beta at 2.0, and each check installs one of its own.
for package in unpreferred preferred inherited inherited-empty exact overridden held newer suite-pinned outranked \
  tied selected selected-explicit; do
  add_package alpha "${package}" 1.0
  add_package beta "${package}" 2.0
done
add_package alpha application 1.0 "Depends: application-library, application-extra"
add_package alpha application-library 1.0
add_package beta application-library 2.0
add_package beta application-extra 2.0
add_package alpha excluded 1.0
add_package beta beta-only 2.0
publish_suite alpha alpha-code 1.0
publish_suite beta beta-code 2.0
# Two suites that share a codename and a version; the sources rank the second below the default priority, as they do
# a backports suite.
for package in pocket-unpreferred pocket later; do
  add_package shared-main "${package}" 1.0
done
add_package shared-backports pocket-unpreferred 2.0
add_package shared-backports pocket 2.0
add_package shared-backports later 2.0 "Suggests: later-suggestion"
add_package shared-backports later-suggestion 2.0
publish_suite shared-main shared 9.0
publish_suite shared-backports shared 9.0 NotAutomatic=yes ButAutomaticUpgrades=yes
# A suite that the repository offers and that no source of the image names.
add_package gamma preferred 3.0
publish_suite gamma gamma-code 3.0
use_suites alpha beta shared-main shared-backports

run_install PACKAGES=unpreferred
check "premise: without a release preference the newer version, which beta offers, is installed" \
  has_version unpreferred 2.0

# Target release prefers a configured release
image_prefers alpha
run_install PACKAGES=inherited
check "with targetRelease omitted the image's default release stays in effect" has_version inherited 1.0
run_install PACKAGES=inherited-empty TARGETRELEASE=""
check "with an empty targetRelease the image's default release stays in effect" has_version inherited-empty 1.0

image_prefers beta
configuration_before="$(apt_configuration)"
run_install PACKAGES=overridden TARGETRELEASE=alpha
check "targetRelease=alpha installs beside an image default release of beta" exited_with 0
check "the install call prefers the release the option names over the image's default release" \
  has_version overridden 1.0
check "the image's configuration is unchanged afterwards" apt_configuration_is "${configuration_before}"
as_root rm "${DEFAULT_RELEASE}"

run_install PACKAGES=preferred TARGETRELEASE=alpha CLEANUP=none
check "targetRelease=alpha installs" exited_with 0
check "only the suite that carries the name is preferred: the package comes from it, not at the newer version of beta" \
  has_version preferred 1.0
check "with targetRelease the refresh covers every configured repository, as it does without the option" \
  index_holds alpha beta shared-main shared-backports
as_root sh -c 'rm -rf /var/lib/apt/lists/*'

run_install PACKAGES=application TARGETRELEASE=alpha
check "a package with dependencies installs under targetRelease=alpha" exited_with 0
check "a dependency that several releases offer comes from the named release" has_version application-library 1.0
check "a dependency that the named release does not offer comes from another release" has_version application-extra 2.0

run_install PACKAGES=exact=2.0 TARGETRELEASE=alpha
check "name=version for a version only another release offers installs under targetRelease=alpha" exited_with 0
check "exactly the listed version is installed" has_version exact 2.0

run_install PACKAGES=pocket-unpreferred
check "premise: without a release preference the version of the higher-ranked suite is installed" \
  has_version pocket-unpreferred 1.0
run_install PACKAGES=pocket TARGETRELEASE=shared
check "targetRelease=shared, a codename two suites carry, installs" exited_with 0
check "both suites are preferred: the newer version comes from the lower-ranked suite" has_version pocket 2.0
run_install PACKAGES=later TARGETRELEASE=9.0 INSTALLSUGGESTS=true
check "targetRelease=9.0, a version two suites carry, prefers both as well" has_version later 2.0

# Later invocation keeps what the earlier one installed
check "premise: the first invocation installed a suggested package from the target release" installed later-suggestion
run_install PACKAGES=later
check "a later invocation with an empty targetRelease and installSuggests=false succeeds" exited_with 0
check "the later invocation does not downgrade the package to the release it would prefer" has_version later 2.0
check "the later invocation does not remove the suggested package" installed later-suggestion

# Target release selects only among configured sources
status_before="$(dpkg_status)"
configuration_before="$(apt_configuration)"
run_install PACKAGES=preferred TARGETRELEASE=nosuch
check "a release that the package index does not hold fails the feature" failed
check "the output names the release" printed "nosuch"
check "the unknown release changes no package" dpkg_status_is "${status_before}"
run_install PACKAGES=preferred TARGETRELEASE=gamma
check "a suite that the repository offers and no source configures fails the feature" failed
check "the output names the unconfigured suite" printed "gamma"
check "the unconfigured suite changes no package" dpkg_status_is "${status_before}"
check "the image's sources are unchanged" apt_configuration_is "${configuration_before}"

# Target release ranks with holds and pins as APT does
run_install PACKAGES=held TARGETRELEASE=alpha
as_root apt-mark hold held >/dev/null
run_install PACKAGES=held TARGETRELEASE=beta
check "a target release that offers a newer version of a held package fails the feature" failed
check "the held package keeps its version" has_version held 1.0

run_install PACKAGES=newer TARGETRELEASE=beta
check "premise: newer is installed at the version of beta" has_version newer 2.0
run_install PACKAGES=newer TARGETRELEASE=alpha
check "a target release whose version is older than the installed one succeeds" exited_with 0
check "the installed newer version stays" has_version newer 2.0

image_pins "Package: *" "Pin: release a=beta" 995
run_install PACKAGES=suite-pinned TARGETRELEASE=alpha
check "a pin above 990 on a suite the target release does not select wins" has_version suite-pinned 2.0

image_pins "Package: excluded" "Pin: version *" -1
status_before="$(dpkg_status)"
run_install PACKAGES=excluded TARGETRELEASE=alpha
check "a negative pin on every version of the package fails the feature" failed
check "the excluded package is not installed" not_installed excluded
check "the negative pin leaves the installed packages unchanged" dpkg_status_is "${status_before}"

image_pins "Package: outranked" "Pin: version 2.0" 600
run_install PACKAGES=outranked TARGETRELEASE=alpha
check "a pin below 990 on a version outside the target release is outranked" has_version outranked 1.0

image_pins "Package: tied" "Pin: version 2.0" 990
run_install PACKAGES=tied TARGETRELEASE=alpha
check "with a pin of exactly 990 on another version the newer of the two versions is installed" has_version tied 2.0

image_pins "Package: *" "Pin: release a=beta" -1
configuration_before="$(apt_configuration)"
run_install PACKAGES=beta-only
check "premise: without a target release the pin of -1 on the suite excludes its package" failed
run_install PACKAGES=beta-only TARGETRELEASE=beta
check "a package that only a suite pinned to -1 offers installs when targetRelease selects that suite" exited_with 0
check "the package is installed from that suite" has_version beta-only 2.0
check "the image's pin is unchanged afterwards" apt_configuration_is "${configuration_before}"
as_root rm "${PREFERENCES}"

# Configuration selected by the environment is honored
echo 'APT::Default-Release "alpha";' >"${SELECTED_CONFIGURATION}"
run_install PACKAGES=selected APT_CONFIG="${SELECTED_CONFIGURATION}"
check "the feature's calls read the configuration file APT_CONFIG names" has_version selected 1.0
run_install PACKAGES=selected-explicit APT_CONFIG="${SELECTED_CONFIGURATION}" TARGETRELEASE=beta
check "an explicit targetRelease overrides the default release of that file" has_version selected-explicit 2.0

reportResults
