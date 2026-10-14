#!/bin/sh
# Scenario test_latest_tagged_alpine_3_22 (scenarios.json): this script first installs less and nano from the Alpine
# branch before the image's, so that they are installed in a version older than the image's repositories offer, and
# gives the image two tagged repositories: @own, a tagged copy of its own first repository, and @edge, Alpine's edge
# branch, which offers a higher version of pv than the image's branch does. It then runs install.sh with latest. Spec
# scenarios "Tagged entry resolves as without the policy", "Both version options are requested" (entries name@tag),
# "Untagged entry does not take a tagged repository's version", and "Later untagged entry keeps a higher tagged
# version".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly PREVIOUS_BRANCH="v3.21"
readonly UNTAGGED_REPOSITORIES="/tmp/repositories.untagged"
readonly EDGE_REPOSITORIES="/tmp/repositories.edge"

# Prints the version the repositories in the file $1 offer of the package $2, read without leaving an index in the
# image. offered_version of installer.sh would also read the tagged repositories this script adds.
version_offered_by() {
  apk --no-cache --repositories-file "$1" search -x "$2" 2>/dev/null | sed -n "s/^$2-\([0-9]\)/\1/p" | head -n 1
}

install_from_branch "${PREVIOUS_BRANCH}" less nano

# The image's repositories as it ships them, the same lines for the edge branch, and both as tagged repositories of
# the image: less and nano come from the first repository, main.
cp /etc/apk/repositories "${UNTAGGED_REPOSITORIES}"
sed 's#/v[0-9][0-9.]*/#/edge/#' "${UNTAGGED_REPOSITORIES}" >"${EDGE_REPOSITORIES}"
main_repository="$(head -n 1 "${UNTAGGED_REPOSITORIES}")"
echo "@own ${main_repository}" >>/etc/apk/repositories
sed 's/^/@edge /' "${EDGE_REPOSITORIES}" >>/etc/apk/repositories

# The versions are read when the test runs: the branches move with every release.
less_installed="$(installed_version less)"
less_offered="$(version_offered_by "${UNTAGGED_REPOSITORIES}" less)"
nano_installed="$(installed_version nano)"
nano_offered="$(version_offered_by "${UNTAGGED_REPOSITORIES}" nano)"
pv_untagged="$(version_offered_by "${UNTAGGED_REPOSITORIES}" pv)"
pv_edge="$(version_offered_by "${EDGE_REPOSITORIES}" pv)"
check "premise: less ${less_installed} is installed" test -n "${less_installed}"
check "premise: the untagged repositories offer another less, ${less_offered}" \
  test "${less_installed}" != "${less_offered}"
check "premise: nano ${nano_installed} is installed" test -n "${nano_installed}"
check "premise: the untagged repositories offer another nano, ${nano_offered}" \
  test "${nano_installed}" != "${nano_offered}"
check "premise: the untagged repositories offer pv ${pv_untagged}" test -n "${pv_untagged}"
check "premise: the repositories tagged edge offer pv ${pv_edge}" test -n "${pv_edge}"
check "premise: the two versions of pv differ" test "${pv_untagged}" != "${pv_edge}"
check "premise: pv is not installed" not_installed pv

run_install PACKAGES="less@own" LATEST=false
check "with latest=false the entry less@own installs" exited_with 0
check "with latest=false less stays at ${less_installed}" installed_in_version less "${less_installed}"
check "less@own is a line of apk's world" in_world "less@own"
state_without_policy="$(apk_state)"
run_install PACKAGES="less@own" LATEST=true
check "with latest=true the entry less@own installs" exited_with 0
check "latest=true leaves the installed versions and apk's world as latest=false left them" \
  apk_state_is "${state_without_policy}"
check "less is still at ${less_installed}, older than the offered ${less_offered}" \
  installed_in_version less "${less_installed}"

run_install PACKAGES="nano@own" UPGRADEPACKAGES=true LATEST=false
check "with upgradePackages=true alone the entry nano@own installs" exited_with 0
check "upgradePackages=true alone raises nano to ${nano_offered}" installed_in_version nano "${nano_offered}"
run_install PACKAGES="less@own" UPGRADEPACKAGES=true LATEST=true
check "with latest=true and upgradePackages=true the entry less@own installs" exited_with 0
check "both options raise less to ${less_offered}, as upgradePackages=true alone raised nano" \
  installed_in_version less "${less_offered}"
check "less@own is still a line of apk's world" in_world "less@own"

run_install PACKAGES=pv LATEST=true
check "with latest=true the list pv installs" exited_with 0
check "pv is at ${pv_untagged}, the highest version of the untagged repositories, not at ${pv_edge}" \
  installed_in_version pv "${pv_untagged}"

run_install PACKAGES="pv@edge"
check "premise: a first installation of pv@edge succeeds" exited_with 0
check "premise: pv is at ${pv_edge}, the version of the tagged repository" installed_in_version pv "${pv_edge}"
run_install PACKAGES=pv LATEST=true
check "a second installation of pv, without the tag and with latest=true, succeeds" exited_with 0
check "pv stays at ${pv_edge}" installed_in_version pv "${pv_edge}"
check "pv is a line of apk's world" in_world pv
check "pv@edge is no longer a line of apk's world" not_in_world "pv@edge"

reportResults
