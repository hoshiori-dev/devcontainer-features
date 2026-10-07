#!/bin/sh
# Scenario test_entry_forms_alpine_3_24 (scenarios.json): this script runs install.sh with one entry of each form the
# specification accepts beside a plain name. Spec scenarios "Pinned version is installed", "Prefix constraint is
# installed", "Range constraint is installed", "Provided name installs a provider", and "Configured tag selects its
# repository". Each run names a package no earlier run installed.
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# The installed version of the package $1 starts with $2.
installed_version_starts_with() {
  installed_version_starts_with_found="$(installed_version "$1")"
  case "${installed_version_starts_with_found}" in
    "$2"*) return 0 ;;
  esac
  echo "$1 is installed in version '${installed_version_starts_with_found}', which does not start with '$2'" >&2
  return 1
}

jq_command_runs() {
  command -v jq >/dev/null && jq --version
}

# Prints the number of lines of /etc/apk/repositories that carry the tag @t and name the community repository.
tagged_community_lines() {
  grep -c '^@t .*/community$' /etc/apk/repositories || true
}

repositories_are() {
  if [ "$(sha256sum /etc/apk/repositories)" != "$1" ]; then
    echo "/etc/apk/repositories changed" >&2
    return 1
  fi
}

# The versions the repositories offer when the test runs: a fixed version would go stale with the next release.
tree_version="$(offered_version tree)"
file_version="$(offered_version file)"
pv_version="$(offered_version pv)"
check "premise: the repositories offer tree" test -n "${tree_version}"
check "premise: the repositories offer file" test -n "${file_version}"
check "premise: the repositories offer pv" test -n "${pv_version}"

run_install PACKAGES="tree=${tree_version}"
check "tree=${tree_version} installs" exited_with 0
check "tree is installed in the pinned version" installed_in_version tree "${tree_version}"
check "tree=${tree_version} is a line of apk's world" in_world "tree=${tree_version}"

# The offered version without its release suffix (-r0).
file_prefix="${file_version%-r*}"
run_install PACKAGES="file~${file_prefix}"
check "file~${file_prefix} installs" exited_with 0
check "file is installed in a version that starts with the prefix" installed_version_starts_with file "${file_prefix}"
check "file~${file_prefix} is a line of apk's world" in_world "file~${file_prefix}"

run_install PACKAGES="pv>=${pv_version}"
check "pv>=${pv_version} installs" exited_with 0
check "pv is installed in the offered version, which satisfies the range" installed_in_version pv "${pv_version}"
check "pv>=${pv_version} is a line of apk's world" in_world "pv>=${pv_version}"

run_install PACKAGES=cmd:jq
check "cmd:jq installs" exited_with 0
check "a jq command is installed and runs" jq_command_runs
check "cmd:jq is a line of apk's world" in_world cmd:jq

# Tag the image's community repository; ripgrep is offered by community only.
sed -i 's|^\(.*/community\)$|@t \1|' /etc/apk/repositories
check "premise: one repository line, community, carries the tag @t" test "$(tagged_community_lines)" = 1
# The untagged name no longer resolves, so only the tag can select the repository.
check "premise: ripgrep does not resolve without the tag" sh -c '! apk --no-cache add --simulate ripgrep'
repositories_before="$(sha256sum /etc/apk/repositories)"
run_install PACKAGES=ripgrep@t
check "ripgrep@t installs" exited_with 0
check "ripgrep is installed" installed ripgrep
check "ripgrep@t is a line of apk's world" in_world ripgrep@t
check "/etc/apk/repositories is unchanged" repositories_are "${repositories_before}"

reportResults
