#!/bin/sh
# Scenario test_latest_lagging_alpine_3_22 (scenarios.json): this script first installs less, nano, and pv from the
# Alpine branch before the image's, so that they and libncursesw, a dependency of less and nano, are installed in a
# version older than the image's repositories offer, and then runs install.sh with latest. Spec scenarios "Listed
# package already installed stays at its version", "Held-back dependency is kept by the upgrade option alone",
# "Held-back dependency fails instead of being kept", "Both version options are requested" (entries without a tag),
# "Entry constraint that excludes the highest version fails", "Listed package is raised to the highest version",
# "Dependencies are raised with the listed package", "Highest version is required without the upgrade option", "Later
# version policy applies to the second installation", and "Entry constraint that admits the highest version succeeds".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly PREVIOUS_BRANCH="v3.21"

# apk's world holds the line $1 exactly once.
in_world_once() {
  [ "$(grep -Fcx -- "$1" /etc/apk/world)" -eq 1 ]
}

install_from_branch "${PREVIOUS_BRANCH}" less nano pv

# The versions are read when the test runs: both branches move with every release.
less_installed="$(installed_version less)"
less_offered="$(offered_version less)"
libncursesw_installed="$(installed_version libncursesw)"
libncursesw_offered="$(offered_version libncursesw)"
pv_installed="$(installed_version pv)"
pv_offered="$(offered_version pv)"
check "premise: less ${less_installed} is installed" test -n "${less_installed}"
check "premise: the repositories offer another less, ${less_offered}" test "${less_installed}" != "${less_offered}"
check "premise: libncursesw ${libncursesw_installed} is installed" test -n "${libncursesw_installed}"
check "premise: the repositories offer another libncursesw, ${libncursesw_offered}" \
  test "${libncursesw_installed}" != "${libncursesw_offered}"
check "premise: pv ${pv_installed} is installed" test -n "${pv_installed}"
check "premise: the repositories offer another pv, ${pv_offered}" test "${pv_installed}" != "${pv_offered}"

run_install PACKAGES=less UPGRADEPACKAGES=false LATEST=false
check "the list less installs with upgradePackages=false and latest=false" exited_with 0
check "less stays at ${less_installed}" installed_in_version less "${less_installed}"

# A first installation pins the dependency in apk's world; the installed version satisfies the pin.
run_install PACKAGES="libncursesw=${libncursesw_installed}"
check "premise: the entry libncursesw=${libncursesw_installed} installs" exited_with 0
check "premise: libncursesw=${libncursesw_installed} is a line of apk's world" \
  in_world "libncursesw=${libncursesw_installed}"

run_install PACKAGES=nano UPGRADEPACKAGES=true LATEST=false
check "with upgradePackages=true alone the list nano installs although its dependency is pinned" exited_with 0
check "the pinned libncursesw stays at ${libncursesw_installed}" \
  installed_in_version libncursesw "${libncursesw_installed}"

state_before="$(apk_state)"
run_install PACKAGES=less LATEST=true
check "with latest=true the list less fails while its dependency is pinned" install_failed
check "the failed run changed neither the installed versions nor apk's world" apk_state_is "${state_before}"
run_install PACKAGES=less LATEST=true UPGRADEPACKAGES=true
check "with latest=true and upgradePackages=true the list less fails as with latest=true alone" install_failed
check "that failed run changed neither the installed versions nor apk's world" apk_state_is "${state_before}"

# A later entry without a constraint replaces the pin.
run_install PACKAGES=libncursesw
check "premise: the entry libncursesw installs" exited_with 0
check "premise: the pin is no longer a line of apk's world" not_in_world "libncursesw=${libncursesw_installed}"
check "premise: libncursesw is still at ${libncursesw_installed}" \
  installed_in_version libncursesw "${libncursesw_installed}"

state_before="$(apk_state)"
run_install PACKAGES="less=${less_installed}" LATEST=true
check "with latest=true the entry less=${less_installed} fails" install_failed
check "the run with less=${less_installed} changed neither the installed versions nor apk's world" \
  apk_state_is "${state_before}"
run_install PACKAGES="less<${less_offered}" LATEST=true
check "with latest=true the entry less<${less_offered} fails" install_failed
check "the run with less<${less_offered} changed neither the installed versions nor apk's world" \
  apk_state_is "${state_before}"

# The earlier runs listed less with latest=false and left it at the older version.
run_install PACKAGES=less LATEST=true UPGRADEPACKAGES=false
check "with latest=true and upgradePackages=false the list less installs" exited_with 0
check "less is at the highest offered version ${less_offered}" installed_in_version less "${less_offered}"
check "its dependency libncursesw is at the highest offered version ${libncursesw_offered}" \
  installed_in_version libncursesw "${libncursesw_offered}"
check "apk's world holds the entry less once" in_world_once less
check "pv, which the list did not name, stays at ${pv_installed}: no whole-system upgrade" \
  installed_in_version pv "${pv_installed}"

run_install PACKAGES="pv>=${pv_installed}" LATEST=true
check "with latest=true the entry pv>=${pv_installed} installs" exited_with 0
check "pv is at the highest offered version ${pv_offered}" installed_in_version pv "${pv_offered}"
check "pv>=${pv_installed} is a line of apk's world" in_world "pv>=${pv_installed}"
run_install PACKAGES="pv=${pv_offered}" LATEST=true
check "with latest=true the entry pv=${pv_offered} installs" exited_with 0
check "pv is still at ${pv_offered}" installed_in_version pv "${pv_offered}"
check "pv=${pv_offered} is a line of apk's world" in_world "pv=${pv_offered}"
run_install PACKAGES="pv~${pv_offered%-r*}" LATEST=true
check "with latest=true the entry pv~${pv_offered%-r*} installs" exited_with 0
check "pv is still at ${pv_offered} after the prefix entry" installed_in_version pv "${pv_offered}"
check "pv~${pv_offered%-r*} is a line of apk's world" in_world "pv~${pv_offered%-r*}"

run_install PACKAGES="pv,docs" LATEST=true
check "with latest=true the list pv,docs installs" exited_with 0
check "pv-doc follows its install-if condition as before" installed pv-doc

run_install PACKAGES=less
check "a later run with the list less and latest omitted succeeds" exited_with 0
check "the later run does not lower less from ${less_offered}" installed_in_version less "${less_offered}"

reportResults
