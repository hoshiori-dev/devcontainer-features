#!/usr/bin/env bash
# Scenario test_target_release_debian (scenarios.json): the container has no network; this script publishes releases of
# its own in it (repository.sh) and runs install.sh against them. Every scenario of the spec requirements "Target
# release prefers a configured release", "Target release selects only among configured sources", and "Target release
# ranks with holds and pins as APT does", and the scenarios "Omitted targetRelease", "Configuration selected by the
# environment is honored", and "Later invocation keeps what the earlier one installed". The design's checks of the
# release check are here as well: a release field that holds a comma, an unknown entry beside an unknown release, a
# release that only a source-package source carries, and a value that is only a part of a release field.
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
readonly CALL_LOG="/tmp/native-calls"
readonly RECORDING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

# The package index holds the source package list of the suite $1 and no binary package list of it.
index_holds_only_sources() {
  if ! compgen -G "/var/lib/apt/lists/*_dists_$1_main_source_Sources*" >/dev/null; then
    echo "the package index holds no source package list of $1" >&2
    return 1
  fi
  if compgen -G "/var/lib/apt/lists/*_dists_$1_main_binary-*_Packages*" >/dev/null; then
    echo "the package index holds a package list of $1" >&2
    return 1
  fi
}

# Runs install.sh as run_install does, behind an apt-get that records each call and forwards it to the image's
# apt-get, and keeps only this run's calls.
run_recorded_install() {
  as_root rm -f "${CALL_LOG}"
  run_install PATH="${RECORDING_PATH}" "$@"
}

# The last recorded run called apt-get, and never to install. The search reads the saved calls: a run that never
# reached apt-get leaves no record, which must not pass for "no install call".
made_no_install_call() {
  local calls
  calls="$(<"${CALL_LOG}")" || return
  if grep --fixed-strings --quiet ' [install]' <<<"${calls}"; then
    printf 'the calls were:\n%s\n' "${calls}" >&2
    return 1
  fi
}

# Two suites with distinct suite names, codenames, and versions. Each package of the list is in alpha at 1.0 and in
# beta at 2.0, and each check installs one of its own.
for package in unpreferred preferred inherited inherited-empty exact overridden held newer suite-pinned outranked \
  tied selected selected-explicit refused; do
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
# A suite whose suite name, codename, and version hold upper- and lower-case letters. Each package of the list is in
# it at 1.0 and in beta at 2.0.
for package in spelled-suite spelled-code spelled-version case-suite case-code case-version; do
  add_package CaseSuite "${package}" 1.0
  add_package beta "${package}" 2.0
done
publish_suite CaseSuite CaseCode 7.1aB
# A suite whose fields are of the kind APT does not compare such a name with: a suite name and a codename that start
# with a digit, and a version that starts with a letter. Its Origin and Label hold a comma followed by text that
# `apt-cache policy` prints as if it were a suite name (a=ghost) and a version (v=8.8) of the release.
add_package 9x refused 0.5
publish_suite 9x 9code v7 "Origin=Scenario,a=ghost" "Label=Scenario,v=8.8"
# A suite that the repository offers and that no source of the image names.
add_package gamma preferred 3.0
publish_suite gamma gamma-code 3.0
# A suite that only a source-package (deb-src) source of the image names. The repository offers its binary package
# list too, with a newer version of a package, and no source of the image configures that list. APT lists the
# release fields of such a source and prefers nothing for it.
add_package source-only refused 4.0
mkdir -p "${REPOSITORY}/dists/source-only/main/source"
cat >"${REPOSITORY}/dists/source-only/main/source/Sources" <<'SOURCES'
Package: refused
Binary: refused
Version: 4.0
Maintainer: Scenario <scenario@example.invalid>
Architecture: all
Format: 3.0 (native)
Files:
 d41d8cd98f00b204e9800998ecf8427e 0 refused_4.0.dsc
Checksums-Sha256:
 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 0 refused_4.0.dsc
Directory: pool/source-only
SOURCES
publish_suite source-only source-only-code 4.0
use_suites alpha beta shared-main shared-backports CaseSuite 9x
echo "deb-src [signed-by=${REPOSITORY_KEYRING}] file:${REPOSITORY} source-only main" \
  | as_root tee -a "${REPOSITORY_SOURCES}" >/dev/null

# An apt-get that records its arguments and then runs the image's apt-get. It forwards every call, because the
# feature's release check reads the index through apt-get.
mkdir /tmp/bin
cat >/tmp/bin/apt-get <<RECORDER
#!/bin/sh
printf 'CALL' >>${CALL_LOG}
for argument do printf ' [%s]' "\${argument}" >>${CALL_LOG}; done
printf '\n' >>${CALL_LOG}
exec $(command -v apt-get) "\$@"
RECORDER
chmod +x /tmp/bin/apt-get

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
  index_holds alpha beta shared-main shared-backports CaseSuite 9x
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

# Letter case of the release name is not significant
run_install PACKAGES=spelled-suite TARGETRELEASE=CaseSuite
check "premise: the suite name in the release's own spelling prefers that release" has_version spelled-suite 1.0
run_install PACKAGES=case-suite TARGETRELEASE=cASEsUITE
check "targetRelease=cASEsUITE, the suite name CaseSuite in another letter case, installs" exited_with 0
check "the release is preferred as with the suite name in its own spelling" has_version case-suite 1.0
run_install PACKAGES=spelled-code TARGETRELEASE=CaseCode
check "premise: the codename in the release's own spelling prefers that release" has_version spelled-code 1.0
run_install PACKAGES=case-code TARGETRELEASE=cASEcODE
check "targetRelease=cASEcODE, the codename CaseCode in another letter case, installs" exited_with 0
check "the release is preferred as with the codename in its own spelling" has_version case-code 1.0
run_install PACKAGES=spelled-version TARGETRELEASE=7.1aB
check "premise: the version in the release's own spelling prefers that release" has_version spelled-version 1.0
run_install PACKAGES=case-version TARGETRELEASE=7.1Ab
check "targetRelease=7.1Ab, the version 7.1aB in another letter case, installs" exited_with 0
check "the release is preferred as with the version in its own spelling" has_version case-version 1.0

# Later invocation keeps what the earlier one installed
check "premise: the first invocation installed a suggested package from the target release" installed later-suggestion
run_install PACKAGES=later
check "a later invocation with an empty targetRelease and installSuggests=false succeeds" exited_with 0
check "the later invocation does not downgrade the package to the release it would prefer" has_version later 2.0
check "the later invocation does not remove the suggested package" installed later-suggestion

# Target release selects only among configured sources
# Each entry is a targetRelease that would make APT prefer no release, and what it is. APT itself accepts the three
# that equal a field of the other kind and refuses the others; the feature's check ends every one of these runs before
# the install call. The entries after the first nine hold the comparison to the whole value: each is a part of a field
# of the kind it is compared with, or equals such a field only when its dot is read as "any character", as a regular
# expression would read it. The error message is told from the installer's log line, which prints
# targetRelease=<value>, by the words around the value.
unpreferred_releases=(
  "nosuch a well-formed name that no release of the package index carries"
  "9x a name starting with a digit that equals a suite name and the version of no release"
  "9code a name starting with a digit that equals a codename and the version of no release"
  "v7 a name starting with a letter that equals a release version and no suite name or codename"
  "ghost a name that only the text after a comma in an Origin field spells as a suite name"
  "8.8 a name that only the text after a comma in a Label field spells as a version"
  "source-only a suite name that only a source-package source carries"
  "source-only-code a codename that only a source-package source carries"
  "4.0 a version that only a source-package source carries"
  "alph a proper prefix of the suite name alpha and of the codename alpha-code"
  "shared-m a proper prefix of the suite name shared-main that is longer than the codename shared"
  "lph a part inside the suite name alpha"
  "eta-cod a part inside the codename beta-code"
  "al.ha a name that equals the suite name alpha only if its dot stands for any character"
  "7.1a a proper prefix of the release version 7.1aB"
  "9 a proper prefix of the release version 9.0"
  "1aB the end of the release version 7.1aB"
  "7.1.B a version that equals the release version 7.1aB only if its second dot stands for any character"
)
configuration_before="$(apt_configuration)"
for unpreferred_release in "${unpreferred_releases[@]}"; do
  name="${unpreferred_release%% *}"
  kind="${unpreferred_release#* }"
  status_before="$(dpkg_status)"
  run_recorded_install PACKAGES=refused TARGETRELEASE="${name}"
  check "targetRelease=${name}, ${kind}, fails the feature with status 1" exited_with 1
  check "targetRelease=${name}: the output names targetRelease and the given value" \
    printed "error: option targetRelease is \"${name}\""
  check "targetRelease=${name}: the install call is not made" made_no_install_call
  check "targetRelease=${name}: no package is installed" not_installed refused
  check "targetRelease=${name}: no package is changed" dpkg_status_is "${status_before}"
done
check "premise: the package index holds the source package list, and no binary package list, of the suite that only \
a source-package source names" index_holds_only_sources source-only

run_recorded_install PACKAGES=nosuchpackage TARGETRELEASE=nosuch
check "an entry that names no package beside a targetRelease that no release carries fails the feature" exited_with 1
check "the entry's failure ends the run: the output names the entry" \
  printed "the entry 'nosuchpackage' names no package"
check "the output does not name targetRelease" did_not_print "targetRelease"

status_before="$(dpkg_status)"
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
