#!/bin/sh
# Scenario fail_unresolvable_entries_alpine_3_24 (scenarios.json): this script runs install.sh with lists that pass
# validation and that apk cannot resolve. Spec scenarios "Unsatisfied range constraint fails", "Malformed constraint
# fails", "Unavailable pinned version fails", "Tag the image does not configure fails", "Unknown package fails",
# "Entry is not read as a package file", and "Unsatisfiable constraint on the second install".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly START_DIR="/start"

# The list $1 fails with a non-zero status, installs neither file nor tree, which every list here names, and leaves
# apk's world, its installed database, and the caches as they were.
fails_without_installing() {
  run_install PACKAGES="$1"
  install_failed && not_installed file && not_installed tree && apk_state_is "${state_before}"
}

repositories_are() {
  if [ "$(sha256sum /etc/apk/repositories)" != "$1" ]; then
    echo "/etc/apk/repositories changed" >&2
    return 1
  fi
}

# START_DIR holds one file, and its name is that of a tree package file.
start_dir_holds_one_tree_package_file() {
  set -- "${START_DIR}"/*
  if [ "$#" -ne 1 ]; then return 1; fi
  case "${1##*/}" in
    tree-*.apk) return 0 ;;
    *) return 1 ;;
  esac
}

# Started from START_DIR, apk itself reads the argument $1 as the package file of that name.
apk_reads_as_package_file() {
  (cd "${START_DIR}" && apk --no-cache add --simulate "$1")
}

# The version the repositories offer when the test runs: a fixed version would go stale with the next release.
tree_version="$(offered_version tree)"
check "premise: the repositories offer tree" test -n "${tree_version}"

state_before="$(apk_state)"
repositories_before="$(sha256sum /etc/apk/repositories)"

check "the list 'file,tree<${tree_version}' fails and installs nothing: no version satisfies the range" \
  fails_without_installing "file,tree<${tree_version}"
check "the list 'file,tree>' fails and installs nothing: the constraint is malformed" \
  fails_without_installing "file,tree>"
check "the list 'file,tree=0.0.0-r0' fails and installs nothing: no repository offers the version" \
  fails_without_installing "file,tree=0.0.0-r0"
check "the list 'file,tree@apkpackagesabsent' fails and installs nothing: the image configures no such tag" \
  fails_without_installing "file,tree@apkpackagesabsent"
check "the run with an unconfigured tag left /etc/apk/repositories unchanged" repositories_are "${repositories_before}"
check "the list 'file,apk-packages-no-such-package,tree' fails and installs nothing: one package is unknown" \
  fails_without_installing "file,apk-packages-no-such-package,tree"

# A signed package file in the directory the feature is started from, listed by its file name.
mkdir "${START_DIR}"
apk --no-cache fetch -q -o "${START_DIR}" tree >/dev/null 2>&1
package_file="$(ls "${START_DIR}")"
check "premise: apk fetch left one tree package file in ${START_DIR}: ${package_file}" \
  start_dir_holds_one_tree_package_file
check "premise: started from ${START_DIR}, apk itself reads the name as that file" \
  apk_reads_as_package_file "${package_file}"
cd "${START_DIR}"
run_install PACKAGES="${package_file}"
cd /
check "started from ${START_DIR} with the entry ${package_file}, the feature fails" install_failed
check "tree is not installed from the file" not_installed tree
check "the run with a file name changed nothing: apk's world, its installed database, and the caches" \
  apk_state_is "${state_before}"

run_install PACKAGES=tree
check "a first run with the list tree succeeds" exited_with 0
installed_tree_version="$(installed_version tree)"
check "premise: the first run installed tree" test -n "${installed_tree_version}"
state_before="$(apk_state)"
run_install PACKAGES="tree<${installed_tree_version}"
check "a second run with 'tree<${installed_tree_version}' fails" install_failed
check "tree stays at ${installed_tree_version}" installed_in_version tree "${installed_tree_version}"
check "the failed second run changed nothing: apk's world, its installed database, and the caches" \
  apk_state_is "${state_before}"

reportResults
