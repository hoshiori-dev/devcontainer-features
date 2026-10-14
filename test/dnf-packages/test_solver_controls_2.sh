#!/usr/bin/env bash
# Scenario test_solver_controls_2 (scenarios.json): this script runs install.sh several times in one container with
# `best` and `parallelDownloads`, and reads the arguments and the environment the installer hands to dnf. Spec scenarios
# "Native best policy is inherited", "Explicit best policy reaches the solver", "Best policy is turned off for the
# invocation", "Pinned version is installed under either policy", "Native parallel downloads are inherited", the
# arguments of "Explicit parallel downloads reach package downloads", "No retry or lock setting is passed", and "Proxy
# and repository variables are inherited".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# A repository the image configures and leaves disabled, and one it enables, for the run that sets every option.
readonly DISABLED_REPOSITORY="crb"
readonly ENABLED_REPOSITORY="extras"
# What a dnf call of the feature must never carry: a retry or lock setting, a switch that skips a lock, a proxy, a
# repository variable, the per-mirror limit, or anything that relaxes a signature or TLS check; and an exclusive or added
# repository or a per-repository switch.
readonly FORBIDDEN_SETTINGS='retries|lock|proxy|setvar|releasever|per_mirror|gpgcheck|sslverify'
readonly FORBIDDEN_SELECTIONS='--repo=|--repoid|repofrompath|\.enabled='
# A PATH on which dnf is a stand-in that saves the environment it runs in and succeeds.
readonly ENVIRONMENT_PATH="/tmp/environment-dnf:/usr/sbin:/usr/bin:/sbin:/bin"
readonly DNF_ENVIRONMENT="/tmp/dnf-environment"

# Prints "<package> <offered edition>" for the first of a few installed packages of which the enabled repositories offer
# a higher version, or nothing when none of them has one. Chosen when the test runs: which package has an update depends
# on the day the image was built. dnf check-update exits with status 100 when it finds one.
upgradable_package() {
  local candidate listing status
  for candidate in ca-certificates gnutls attr tzdata gzip expat; do
    status=0
    listing="$(dnf -q check-update "${candidate}" 2>/dev/null)" || status=$?
    if [[ "${status}" -eq 100 ]]; then
      echo "${candidate} $(awk -v prefix="${candidate}." 'index($1, prefix) == 1 { print $2; exit }' <<<"${listing}")"
      return 0
    fi
  done
}

# The stand-in dnf ran in an environment that holds exactly $1 repository variables and proxy settings.
dnf_environment_holds_settings() {
  [[ "$(grep --extended-regexp --count '^(DNF_VAR_|[A-Za-z_]*proxy=)' "${DNF_ENVIRONMENT}")" -eq "$1" ]]
}

# Prints "<package> <oldest edition> <newest edition>" for the first of a few packages that the repositories offer in
# more than one edition ("<version>-<release>", after "<epoch>:" where the package has one). Chosen when the test runs,
# so that no fixed version goes stale.
two_edition_package() {
  local candidate listing editions count
  for candidate in file bc libfuse3-3 openssl-libs curl-minimal glibc; do
    listing="$(dnf list --showduplicates "${candidate}" 2>/dev/null)" || continue
    editions="$(awk -v prefix="${candidate}." 'index($1, prefix) == 1 { print $2 }' <<<"${listing}" | sort -u -V)"
    count="$(wc -l <<<"${editions}")"
    if [[ "${count}" -gt 1 ]]; then
      echo "${candidate} $(head -n 1 <<<"${editions}") $(tail -n 1 <<<"${editions}")"
      return 0
    fi
  done
  echo "none of the candidate packages is offered in two editions" >&2
  return 1
}

# No dnf call of the last recorded run, of any kind, carries a forbidden argument.
no_call_is_forbidden() {
  if grep --extended-regexp -e "${FORBIDDEN_SETTINGS}" -e "${FORBIDDEN_SELECTIONS}" "${DNF_CALLS}" >&2; then
    echo "a dnf call carries a forbidden argument" >&2
    return 1
  fi
}

# The stand-in dnf ran in an environment that holds the line $1.
dnf_environment_has() {
  grep --line-regexp --fixed-strings --quiet -e "$1" "${DNF_ENVIRONMENT}"
}

record_dnf_calls
configuration_before="$(dnf_configuration)"

run_recorded_install PACKAGES=tree
check "tree installs with best and parallelDownloads omitted" exited_with 0
check "with best omitted no best-version override is passed" install_call_lacks 'best'
check "with parallelDownloads omitted no download-concurrency override is passed" install_call_lacks 'parallel'
check "with every new option omitted no dnf call carries a retry, lock, proxy, or variable setting" no_call_is_forbidden
run_recorded_install PACKAGES=tree BEST=inherit PARALLELDOWNLOADS=""
check "tree installs with best=inherit and an empty parallelDownloads" exited_with 0
check "with best=inherit no best-version override is passed" install_call_lacks 'best'
check "with an empty parallelDownloads no download-concurrency override is passed" install_call_lacks 'parallel'

run_recorded_install PACKAGES=tree BEST=true
check "best=true sets best to True on the install call" install_call_has "--setopt=best=True"
run_recorded_install PACKAGES=tree BEST=false
check "best=false sets best to False on the install call" install_call_has "--setopt=best=False"

selection="$(upgradable_package)"
if [[ -n "${selection}" ]]; then
  read -r package offered <<<"${selection}"
  before="$(version_of "${package}")"
  run_install PACKAGES="${package}" BEST=false
  check "best=false succeeds for the installed ${package}, of which ${offered} is offered" exited_with 0
  check "best=false leaves ${package} at its installed version ${before}" has_version "${package}" "${before}"
  run_install PACKAGES="${package}" BEST=true
  check "best=true succeeds for the installed ${package}" exited_with 0
  check "best=true upgrades ${package} to the offered ${offered#*:}" has_version "${package}" "${offered#*:}"
else
  echo "no candidate package has an update today: the arguments above stand for the two best policies"
fi

selection="$(two_edition_package)"
read -r package older newer <<<"${selection}"
run_install PACKAGES="${package}" CLEANUP=none
check "the installation of ${package} without a version succeeds" exited_with 0
run_install PACKAGES="${package}-${older}" BEST=true CLEANUP=none
check "best=true with the pin ${package}-${older} succeeds" exited_with 0
check "under best=true ${package} is at the pinned version ${older#*:}" has_version "${package}" "${older#*:}"
run_install PACKAGES="${package}-${newer}" BEST=false
check "best=false with the pin ${package}-${newer} succeeds" exited_with 0
check "under best=false ${package} is at the pinned version ${newer#*:}" has_version "${package}" "${newer#*:}"

run_recorded_install PACKAGES=ed PARALLELDOWNLOADS=2
check "ed installs with parallelDownloads=2" exited_with 0
check "parallelDownloads=2 sets the bound for dnf as a whole" install_call_has "--setopt=max_parallel_downloads=2"
check "parallelDownloads=2 sets the bound for every enabled repository" \
  install_call_has "--setopt=*.max_parallel_downloads=2"

# Every option at a value other than its default.
run_recorded_install PACKAGES=time INSTALLWEAKDEPS=true REFRESHPOLICY=always CLEANUP=packages NETWORKTIMEOUT=30 \
  BEST=true ENABLEREPOSITORIES="${DISABLED_REPOSITORY}" DISABLEREPOSITORIES="${ENABLED_REPOSITORY}" PARALLELDOWNLOADS=20
check "time installs with every option set" exited_with 0
check "with every option set no dnf call carries a retry, lock, proxy, or variable setting" no_call_is_forbidden
check "no control value is written to the dnf configuration" dnf_configuration_is "${configuration_before}"

mkdir "${ENVIRONMENT_PATH%%:*}"
printf '#!/bin/sh\nenv >%s\n' "${DNF_ENVIRONMENT}" >"${ENVIRONMENT_PATH%%:*}/dnf"
chmod +x "${ENVIRONMENT_PATH%%:*}/dnf"
# env -i: the installer starts from an empty environment, so dnf sees what this run names and what the installer adds.
run_install -i PATH="${ENVIRONMENT_PATH}" PACKAGES=bc CLEANUP=none LC_ALL=C.UTF-8 DNF_VAR_feature_test=kept \
  https_proxy=http://proxy.invalid:3128 no_proxy=localhost
check "the run with a stand-in dnf succeeds" exited_with 0
check "a repository variable of the build environment reaches dnf unchanged" \
  dnf_environment_has "DNF_VAR_feature_test=kept"
check "a proxy of the build environment reaches dnf unchanged" \
  dnf_environment_has "https_proxy=http://proxy.invalid:3128"
check "a proxy exception of the build environment reaches dnf unchanged" dnf_environment_has "no_proxy=localhost"
check "the locale of the build environment reaches dnf unchanged" dnf_environment_has "LC_ALL=C.UTF-8"
check "the feature adds no repository variable and no proxy: dnf's environment holds those three" \
  dnf_environment_holds_settings 3

reportResults
