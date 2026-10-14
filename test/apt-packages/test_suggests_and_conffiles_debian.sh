#!/usr/bin/env bash
# Scenario test_suggests_and_conffiles_debian (scenarios.json): the container has no network; this script publishes
# packages of its own in it (repository.sh) and runs install.sh against them. Every scenario of the spec requirement
# "Configuration file policy covers dpkg conffiles"; the scenarios "Omitted installSuggests", "Omitted conffilePolicy",
# "Suggested packages are left out", "Suggested packages are installed", "Suggestions and recommendations are selected
# independently", "Changed configuration file is kept", "Changed configuration file is replaced", "Image setting does
# not defeat keeping", "Image setting does not defeat replacing", and "File managed by maintainer scripts is outside the
# policy".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"
# shellcheck source=/dev/null
source "$(dirname "$0")/repository.sh"

readonly IMAGE_CONTENT="changed in the image"
readonly SUGGESTS_SETTING="/etc/apt/apt.conf.d/99-scenario-suggests"
readonly APT_DPKG_SETTING="/etc/apt/apt.conf.d/99-scenario-dpkg-options"
readonly DPKG_SETTING="/etc/dpkg/dpkg.cfg.d/scenario"
# Each of these packages is published at 1.0 and 2.0 with the conffile /etc/<package>.conf, and each check upgrades or
# installs one of its own.
readonly UPGRADED=(
  kept kept-by-default replaced restored unchanged-keep unchanged-replace returned-keep returned-replace
  premise-packaged premise-installed defended-dpkg defended-apt enforced-dpkg enforced-apt
)
readonly NEVER_INSTALLED=(fresh-keep fresh-replace claimed-keep claimed-replace)

# The image holds other content than the package ships at the conffile path of the package $1.
image_changes() {
  echo "${IMAGE_CONTENT}" | as_root tee "/etc/$1.conf" >/dev/null
}

# The file $1 holds the content the image gave the conffile.
is_the_image_file() {
  if [[ "$(<"$1")" != "${IMAGE_CONTENT}" ]]; then
    echo "$1 holds \"$(<"$1")\", not the image's content" >&2
    return 1
  fi
}

# The file $1 holds the conffile that the package $2 ships at version 2.0.
is_the_packaged_file() {
  if [[ "$(<"$1")" != "packaged by $2 2.0" ]]; then
    echo "$1 holds \"$(<"$1")\", not the content $2 2.0 ships" >&2
    return 1
  fi
}

# dpkg left no .dpkg-dist or .dpkg-old file beside the conffile of the package $1.
no_file_beside() {
  if compgen -G "/etc/$1.conf.dpkg-*" >/dev/null; then
    echo "a .dpkg-* file is beside /etc/$1.conf" >&2
    return 1
  fi
}

# Adds the package $1 at version 1.0, which keeps the configuration file /etc/$1.conf through its maintainer script and
# not as a conffile: the script writes the file only where none exists, and records what it was told about
# configuration files in /var/lib/$1.environment.
add_scripted_package() {
  local tree
  tree="$(package_tree main "$1" 1.0)"
  cat >"${tree}/DEBIAN/postinst" <<POSTINST
#!/bin/sh
set -e
printf '%s %s %s\n' "\${DEBIAN_FRONTEND-unset}" "\${UCF_FORCE_CONFFOLD-unset}" "\${UCF_FORCE_CONFFNEW-unset}" \\
  >/var/lib/$1.environment
if [ ! -e /etc/$1.conf ]; then echo "written by the maintainer script" >/etc/$1.conf; fi
POSTINST
  chmod 0755 "${tree}/DEBIAN/postinst"
  pack "${tree}"
}

# The maintainer script of the package $1 ran without a terminal frontend and without a setting for its file.
script_was_given_no_setting() {
  [[ "$(<"/var/lib/$1.environment")" == "noninteractive unset unset" ]]
}

for package in "${UPGRADED[@]}"; do
  add_conffile_package main "${package}" 1.0
  add_conffile_package main "${package}" 2.0
done
for package in "${NEVER_INSTALLED[@]}"; do
  add_conffile_package main "${package}" 2.0
done
add_scripted_package scripted-keep
add_scripted_package scripted-replace
add_package main quiet 1.0 "Suggests: quiet-suggestion"
add_package main quiet-suggestion 1.0
add_package main eager 1.0 "Suggests: eager-suggestion"
add_package main eager-suggestion 1.0
add_package main mixed 1.0 "Suggests: mixed-suggestion" "Recommends: mixed-recommendation"
add_package main mixed-suggestion 1.0
add_package main mixed-recommendation 1.0
publish_suite main main-code 1.0
use_suites main
configuration_before="$(apt_configuration)"

# Suggested packages
echo 'APT::Install-Suggests "true";' | as_root tee "${SUGGESTS_SETTING}" >/dev/null
run_install PACKAGES=quiet
check "with installSuggests omitted the listed package is installed" installed quiet
check "its suggested package is not, also on an image whose APT configuration enables suggestions" \
  not_installed quiet-suggestion
as_root rm "${SUGGESTS_SETTING}"
run_install PACKAGES=eager INSTALLSUGGESTS=true
check "with installSuggests=true the listed package is installed" installed eager
check "its suggested package is installed with it" installed eager-suggestion
run_install PACKAGES=mixed INSTALLSUGGESTS=true INSTALLRECOMMENDS=false
check "with installSuggests=true and installRecommends=false the suggested package is installed" \
  installed mixed-suggestion
check "the recommended package is not" not_installed mixed-recommendation

# Conffiles on an upgrade
first_versions="$(printf '%s=1.0,' "${UPGRADED[@]}")"
run_install PACKAGES="${first_versions}"
check "premise: the first versions of the conffile packages install" exited_with 0
for package in kept kept-by-default replaced returned-keep returned-replace premise-packaged premise-installed \
  defended-dpkg defended-apt enforced-dpkg enforced-apt; do
  image_changes "${package}"
done
as_root rm /etc/restored.conf

run_install PACKAGES=kept CONFFILEPOLICY=keep </dev/null
check "an upgrade over a changed conffile completes without input under conffilePolicy=keep" exited_with 0
check "premise: kept was upgraded" has_version kept 2.0
check "the changed file is unchanged" is_the_image_file /etc/kept.conf
check "the packaged version is beside it with the suffix .dpkg-dist" is_the_packaged_file /etc/kept.conf.dpkg-dist kept
run_install PACKAGES=kept-by-default </dev/null
check "with conffilePolicy omitted a changed conffile is kept on an upgrade" is_the_image_file /etc/kept-by-default.conf

run_install PACKAGES=replaced CONFFILEPOLICY=replace </dev/null
check "an upgrade over a changed conffile completes without input under conffilePolicy=replace" exited_with 0
check "the file holds the packaged content" is_the_packaged_file /etc/replaced.conf replaced
check "the image's version is beside it with the suffix .dpkg-old" is_the_image_file /etc/replaced.conf.dpkg-old

run_install PACKAGES=restored CONFFILEPOLICY=replace </dev/null
check "with conffilePolicy=replace a conffile deleted in the image is installed again" \
  is_the_packaged_file /etc/restored.conf restored

for policy in keep replace; do
  run_install PACKAGES="unchanged-${policy}" CONFFILEPOLICY="${policy}" </dev/null
  check "a conffile the image did not change is upgraded under conffilePolicy=${policy}" \
    is_the_packaged_file "/etc/unchanged-${policy}.conf" "unchanged-${policy}"
  check "no .dpkg-dist or .dpkg-old file appears under conffilePolicy=${policy}" no_file_beside "unchanged-${policy}"
done

# Conffiles of a package that is not installed
for policy in keep replace; do
  run_install PACKAGES="fresh-${policy}" CONFFILEPOLICY="${policy}" </dev/null
  check "a new package's conffile is installed as packaged under conffilePolicy=${policy}" \
    is_the_packaged_file "/etc/fresh-${policy}.conf" "fresh-${policy}"
  check "no .dpkg-dist or .dpkg-old file appears for a new package under conffilePolicy=${policy}" \
    no_file_beside "fresh-${policy}"
done

image_changes claimed-keep
image_changes claimed-replace
as_root apt-get remove --yes -qq returned-keep returned-replace >/dev/null
check "premise: returned-keep was removed and its changed conffile stays" is_the_image_file /etc/returned-keep.conf
for package in claimed returned; do
  run_install PACKAGES="${package}-keep" CONFFILEPOLICY=keep </dev/null
  check "${package}-keep installs over an existing file at its conffile path" exited_with 0
  check "conffilePolicy=keep leaves the image's file of ${package}-keep" is_the_image_file "/etc/${package}-keep.conf"
  check "the packaged file of ${package}-keep is beside it with the suffix .dpkg-dist" \
    is_the_packaged_file "/etc/${package}-keep.conf.dpkg-dist" "${package}-keep"
  run_install PACKAGES="${package}-replace" CONFFILEPOLICY=replace </dev/null
  check "${package}-replace installs over an existing file at its conffile path" exited_with 0
  check "conffilePolicy=replace installs the packaged file of ${package}-replace" \
    is_the_packaged_file "/etc/${package}-replace.conf" "${package}-replace"
  check "the image's file of ${package}-replace is beside it with the suffix .dpkg-old" \
    is_the_image_file "/etc/${package}-replace.conf.dpkg-old"
done

# A file that maintainer scripts manage
for policy in keep replace; do
  image_changes "scripted-${policy}"
  run_install PACKAGES="scripted-${policy}" CONFFILEPOLICY="${policy}" </dev/null
  check "a package that manages its file by script installs without input under conffilePolicy=${policy}" exited_with 0
  check "its script got no setting for the file under conffilePolicy=${policy}" \
    script_was_given_no_setting "scripted-${policy}"
  check "the file is handled as the package decides under conffilePolicy=${policy}: its script keeps it" \
    is_the_image_file "/etc/scripted-${policy}.conf"
  check "dpkg writes no file beside it under conffilePolicy=${policy}" no_file_beside "scripted-${policy}"
done
check "no run so far changed the image's APT or dpkg configuration" apt_configuration_is "${configuration_before}"

# Image settings that select the opposite handling
echo 'force-confnew' | as_root tee "${DPKG_SETTING}" >/dev/null
as_root apt-get update -qq
as_root apt-get install --yes -qq premise-packaged </dev/null >/dev/null
check "premise: a dpkg configuration with force-confnew alone selects the packaged version" \
  is_the_packaged_file /etc/premise-packaged.conf premise-packaged
as_root sh -c 'rm -rf /var/lib/apt/lists/*'
run_install PACKAGES=defended-dpkg CONFFILEPOLICY=keep </dev/null
check "conffilePolicy=keep keeps the file when the image's dpkg configuration selects the packaged version" \
  is_the_image_file /etc/defended-dpkg.conf
as_root rm "${DPKG_SETTING}"
echo 'Dpkg::Options { "--force-confnew"; };' | as_root tee "${APT_DPKG_SETTING}" >/dev/null
run_install PACKAGES=defended-apt CONFFILEPOLICY=keep </dev/null
check "conffilePolicy=keep keeps the file when the image's APT configuration selects the packaged version" \
  is_the_image_file /etc/defended-apt.conf

printf 'force-confdef\nforce-confold\n' | as_root tee "${DPKG_SETTING}" >/dev/null
as_root rm "${APT_DPKG_SETTING}"
as_root apt-get update -qq
as_root apt-get install --yes -qq premise-installed </dev/null >/dev/null
check "premise: a dpkg configuration with force-confdef and force-confold alone keeps the installed version" \
  is_the_image_file /etc/premise-installed.conf
as_root sh -c 'rm -rf /var/lib/apt/lists/*'
run_install PACKAGES=enforced-dpkg CONFFILEPOLICY=replace </dev/null
check "conffilePolicy=replace replaces the file when the image's dpkg configuration selects the default action" \
  is_the_packaged_file /etc/enforced-dpkg.conf enforced-dpkg
as_root rm "${DPKG_SETTING}"
echo 'Dpkg::Options { "--force-confdef"; "--force-confold"; };' | as_root tee "${APT_DPKG_SETTING}" >/dev/null
run_install PACKAGES=enforced-apt CONFFILEPOLICY=replace </dev/null
check "conffilePolicy=replace replaces the file when the image's APT configuration selects the installed version" \
  is_the_packaged_file /etc/enforced-apt.conf enforced-apt

reportResults
