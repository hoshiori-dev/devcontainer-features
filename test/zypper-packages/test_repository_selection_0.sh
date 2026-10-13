#!/usr/bin/env bash
# Scenario test_repository_selection_0 (scenarios.json): this script runs install.sh with the option repositories in
# one container, with the image's own aliases read when it runs, and with repositories it adds: a directory of package
# files the image's repository offers, one at an address that answers nothing, and one whose name is another's alias.
# For some runs zypper is a stand-in that records its calls and then runs the image's zypper (zypper_recorder.sh).
# Spec scenarios of "Repository selection restricts the installation": "Empty repositories uses every enabled
# repository", "Selected repository provides the packages", "Package outside the selection fails", "Dependency outside
# the selection fails", "Unknown alias fails before installation", "Disabled repository is not enabled", "Alias that
# is another repository's name fails", "Unselected repository is not refreshed", "Selected repository that cannot be
# refreshed fails", "Cached metadata is required only for the selection", "Conflict with a package of an unselected
# repository fails", and "Cleanup covers every repository"; and "Spaces, empty items, and repeated aliases in
# repositories", "Exact names combine with a repository selection", "Selection and network controls do not carry
# over", and "Selection of the second install keeps earlier packages".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly RECORD_DIR="/tmp/zypper-record"
# A PATH on which zypper is the recording stand-in.
readonly RECORDER_PATH="/tmp/recorder:/usr/sbin:/usr/bin:/sbin:/bin"
# A directory of package files that zypper reads as a repository without metadata of its own.
readonly FIXTURE="/tmp/fixture"
readonly CLASH_FILE="/etc/zypp/repos.d/clash.repo"

# Runs install.sh with a stand-in on PATH that records each zypper call and then runs the image's zypper.
run_recorded() {
  rm -rf "${RECORD_DIR}"
  mkdir "${RECORD_DIR}"
  echo yes >"${RECORD_DIR}/real"
  run_install PATH="${RECORDER_PATH}" "$@"
}

# The stand-in recorded a call with exactly the arguments $1.
called_with() {
  if ! grep -qxF -- "$1" "${RECORD_DIR}/calls"; then
    printf 'no zypper call had the arguments: %s\nthe calls were:\n%s\n' "$1" "$(<"${RECORD_DIR}/calls")" >&2
    return 1
  fi
}

# No recorded call had the variable $1 in its environment.
no_call_had() {
  if grep -q "^$1=" "${RECORD_DIR}"/env.*; then
    echo "a zypper call had $1 in its environment" >&2
    return 1
  fi
}

# No recorded call ran while a temporary configuration file of the feature existed.
no_call_saw_an_override() {
  local record
  for record in "${RECORD_DIR}"/override.* "${RECORD_DIR}"/run-zypp.*; do
    if [[ -e "${record}" ]]; then
      echo "a zypper call ran while /run/zypp existed" >&2
      return 1
    fi
  done
}

# Prints the value of the attribute $2 of the repository with the alias $1 in zypper's listing.
repository_attribute() {
  zypper --xmlout --non-interactive --no-refresh repos \
    | sed -n "/<repo alias=\"$1\"/s/.* $2=\"\\([^\"]*\\)\".*/\\1/p"
}

# The run with the alias $1, which no enabled repository has, failed with status 1 and named it, before any metadata
# or package file was downloaded and before any package changed.
refused_before_installation() {
  exited_with 1 && printed "'$1'" && no_raw_metadata && no_package_files && rpm_database_is "${database_before}"
}

# The repository definitions are as the digest $1 says.
repository_definitions_are() {
  if [[ "$(zypp_configuration)" != "$1" ]]; then
    echo "a repository definition changed" >&2
    return 1
  fi
}

mkdir /tmp/recorder
install -m 0755 "$(dirname "$0")/zypper_recorder.sh" /tmp/recorder/zypper

oss="$(enabled_alias repo-oss)"
openh264="$(enabled_alias repo-openh264)"
check "premise: the image enables a repository whose alias ends in repo-oss" test -n "${oss}"
check "premise: the image enables a repository whose alias ends in repo-openh264" test -n "${openh264}"
disabled="$(zypper --xmlout --non-interactive --no-refresh repos | sed -n '/enabled="0"/s/.*alias="\([^"]*\)".*/\1/p' \
  | sed -n 1p)"
check "premise: the image defines a repository it disables" test -n "${disabled}"

# The fixture: file needs libmagic1, which only the image's repository offers, and coreutils-single conflicts with
# coreutils, which the image installed from there. Both files carry the signature of the image's repository.
zypper --non-interactive refresh
zypper --non-interactive --no-refresh download file coreutils-single
mkdir "${FIXTURE}"
while read -r package_file; do
  cp "${package_file}" "${FIXTURE}/"
done < <(package_files)
zypper --non-interactive clean --all
printf '[fixture]\nname=fixture directory\nenabled=1\nautorefresh=1\nbaseurl=dir://%s\ntype=plaindir\n' "${FIXTURE}" \
  >/etc/zypp/repos.d/fixture.repo
check "premise: coreutils, with which coreutils-single conflicts, is installed" installed coreutils
check "premise: libmagic1, which file needs, is not installed" not_installed libmagic1
database_before="$(rpm_database)"
definitions_before="$(zypp_configuration)"

# Aliases no enabled repository has: another letter case, an alias that does not exist, and, where they are
# well-formed, the alias without its service prefix (Leap) and the repository's name (Tumbleweed).
unknown_aliases=("${oss^^}" "no-such-repository")
if [[ "${oss#*:}" != "${oss}" ]]; then unknown_aliases+=("${oss#*:}"); fi
oss_name="$(repository_attribute "${oss}" name)"
if [[ "${oss_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._:+-]*$ ]]; then unknown_aliases+=("${oss_name}"); fi
check "premise: one alias is tried besides the upper-case one and the one that does not exist" \
  test "${#unknown_aliases[@]}" -eq 3
for alias in "${unknown_aliases[@]}"; do
  run_install PACKAGES=bc REPOSITORIES="${alias}"
  check "repositories=${alias}, the alias of no enabled repository, fails with status 1 before anything changes" \
    refused_before_installation "${alias}"
done

run_install PACKAGES=bc REPOSITORIES="${oss},${disabled}"
check "repositories naming the disabled ${disabled} fails with status 1 before anything changes" \
  refused_before_installation "${disabled}"
check "the repository ${disabled} is still disabled" test "$(repository_attribute "${disabled}" enabled)" = 0
check "no repository definition changed" repository_definitions_are "${definitions_before}"

for enabled in 1 0; do
  printf '[clash]\nname=%s\nenabled=%s\nautorefresh=0\nbaseurl=dir://%s\n' "${oss}" "${enabled}" "${FIXTURE}" \
    >"${CLASH_FILE}"
  run_install PACKAGES=bc REPOSITORIES="${oss}"
  check "repositories=${oss} fails with status 1 while another repository (enabled=${enabled}) has that name" \
    refused_before_installation "${oss}"
done
rm "${CLASH_FILE}"

run_install PACKAGES=file,bc REPOSITORIES="${openh264}"
check "bc, which only an unselected repository offers, fails with repositories=${openh264}" failed
check "with a package outside the selection nothing is installed" rpm_database_is "${database_before}"

run_install PACKAGES=file REPOSITORIES=fixture
check "file, whose dependency libmagic1 only an unselected repository offers, fails with repositories=fixture" failed
check "with a dependency outside the selection nothing is installed" rpm_database_is "${database_before}"
# On Tumbleweed the image's own repositories hold such a pair: the plugin needs GStreamer, which repo-oss offers.
if grep --quiet Tumbleweed /etc/os-release; then
  run_install PACKAGES=gstreamer-plugin-openh264 REPOSITORIES="${openh264}"
  check "gstreamer-plugin-openh264, whose dependencies only repo-oss offers, fails with repositories=${openh264}" \
    failed
  check "with that dependency outside the selection nothing is installed" rpm_database_is "${database_before}"
fi

run_install PACKAGES=coreutils-single REPOSITORIES=fixture
check "coreutils-single, which conflicts with coreutils from an unselected repository, fails" failed
check "the installed coreutils stays" installed coreutils
check "the conflict changes no installed package" rpm_database_is "${database_before}"

zypper --non-interactive clean --all
run_recorded PACKAGES=bc REPOSITORIES=" ${oss} ,, ${oss} " CLEANUP=none
check "repositories naming ${oss} twice, with spaces and an empty item, succeeds" exited_with 0
check "bc, which the selected repository offers, is installed" installed bc
check "the refresh selects ${oss} once" called_with "--non-interactive refresh --repo ${oss}"
check "the installation selects ${oss} once" \
  called_with "--non-interactive --no-refresh install --no-recommends --repo ${oss} -- bc"
check "only the metadata of ${oss} was downloaded" raw_metadata_only_of "${oss}"

# One enabled repository answers nothing: the port is closed.
zypper --non-interactive addrepo http://127.0.0.1:9/ unavailable >/dev/null
run_install PACKAGES=tree REFRESHPOLICY=always CLEANUP=none
check "premise: with an empty repositories the repository that cannot be refreshed fails the feature" failed
run_install PACKAGES=tree REPOSITORIES="${oss}" REFRESHPOLICY=always CLEANUP=none
check "with repositories=${oss} the unselected repository that cannot be refreshed does not fail the feature" \
  exited_with 0
check "tree is installed" installed tree
check "the run did not name the unselected repository" did_not_print unavailable
run_install PACKAGES=unzip REPOSITORIES="${oss},unavailable"
check "with the repository that cannot be refreshed selected beside ${oss} the feature fails" failed
check "no unzip is installed" not_installed unzip

zypper --non-interactive clean --all
zypper --non-interactive refresh --repo "${oss}"
run_install PACKAGES=unzip REFRESHPOLICY=never CLEANUP=none
check "premise: refreshPolicy=never fails while an enabled repository has no cached metadata" failed
run_install PACKAGES=unzip REPOSITORIES="${oss}" REFRESHPOLICY=never CLEANUP=none
check "refreshPolicy=never with repositories=${oss} needs cached metadata of ${oss} only" exited_with 0
check "unzip is installed from the cached metadata" installed unzip
check "no metadata of another repository was downloaded" raw_metadata_only_of "${oss}"
zypper --non-interactive removerepo unavailable >/dev/null

run_install PACKAGES=less,pkgconfig REPOSITORIES="${oss}" EXACTNAMES=true CLEANUP=none
check "with exactNames=true and repositories=${oss} a capability of that repository fails the list" failed
check "no less is installed" not_installed less

zypper --non-interactive refresh
check "premise: the image holds cached metadata of the unselected ${openh264}" \
  test -d "/var/cache/zypp/raw/${openh264}"
run_install PACKAGES=zip REPOSITORIES="${oss}"
check "zip installs with repositories=${oss} and cleanup=all" exited_with 0
check "cleanup=all removes the raw metadata of the unselected repositories as well" no_raw_metadata
check "cleanup=all removes the parsed metadata of every repository" no_metadata

# A second and a third installation: bc came from ${oss}; the second selects another repository and sets every
# selection and network control, and the third sets none of them. Neither installs a package that ships a file under
# /etc/zypp or a signing key.
configuration_before="$(libzypp_configuration)"
keys_before="$(rpm -qa 'gpg-pubkey*' | sort)"
run_recorded PACKAGES=mozilla-openh264 REPOSITORIES="${openh264}" EXACTNAMES=true LOCKTIMEOUT=5 CONNECTTIMEOUT=30 \
  TRANSFERTIMEOUT=60 DOWNLOADRETRIES=1 CLEANUP=none
check "a later installation that selects ${openh264} succeeds" exited_with 0
check "its refresh selects ${openh264}" called_with "--non-interactive refresh --repo ${openh264}"
check "mozilla-openh264, which that repository offers, is installed" installed mozilla-openh264
check "bc, installed earlier from ${oss}, is still installed" installed bc
check "only the metadata of ${openh264} was downloaded" raw_metadata_only_of "${openh264}"

check "premise: pkgconf-pkg-config, which provides pkgconfig, is not installed" not_installed pkgconf-pkg-config
run_recorded PACKAGES=pkgconfig CLEANUP=none
check "a later installation with the selection and network controls at their defaults succeeds" exited_with 0
check "it refreshes every enabled repository" called_with "--non-interactive refresh"
check "it installs without --name and --repo" \
  called_with "--non-interactive --no-refresh install --no-recommends -- pkgconfig"
check "pkgconf-pkg-config, which only a repository outside the earlier selection offers, is installed" \
  installed pkgconf-pkg-config
check "it holds metadata of the repositories outside the earlier selection" test -d "/var/cache/zypp/raw/${oss}"
check "none of its calls gets a lock wait" no_call_had ZYPP_LOCK_TIMEOUT
check "none of its calls finds a file the earlier installation wrote" no_call_saw_an_override
check "nothing is left of a temporary configuration file" no_override_left
check "after both installations the directories libzypp reads configuration from are as before them" \
  libzypp_configuration_is "${configuration_before}"
check "after both installations the RPM database trusts the same keys" \
  test "$(rpm -qa 'gpg-pubkey*' | sort)" = "${keys_before}"

reportResults
