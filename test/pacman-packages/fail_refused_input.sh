#!/usr/bin/env bash
# Scenario fail_refused_input (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh with input that validation refuses, and with the accepted forms next to it. Spec scenarios "URL or path is
# refused", "Option-like entry is refused", "Shell metacharacters and inner whitespace are refused", "Malformed
# repository qualifier is refused", "Repository-qualified entry is accepted", "Invalid control fails before any
# change", "Empty list ignores installation controls", and "Parallel download boundaries are validated".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# URLs and paths: an entry holding "/" that starts with "/" or ".", holds "://", or holds a second "/".
readonly REFUSED_PATHS=(
  "/tmp/bc.pkg.tar.zst" "./bc.pkg.tar.zst" "${ARCHIVE}/b/bc/bc.pkg.tar.zst" "file:///tmp/bc.pkg.tar.zst" "/bc" "../bc"
  ".cache/bc" "extra//bc" "extra/os/bc" "cache/pkg/bc.pkg.tar.zst"
)

# Entries with exactly one "/" that are no path or URL: a repository part that starts with or holds a character
# outside its set, an empty repository or target part, and a target part that is no accepted target. The entry before
# the last starts with a non-ASCII letter, c with acute, as its UTF-8 bytes.
readonly MALFORMED_QUALIFIERS=(
  "-extra/bc" "_extra/bc" "ex@tra/bc" "extra:/bc" "extra>=1/bc" "ext ra/bc" "extra/" "extra/-bc" "extra/.bc"
  "extra/b*" "extra/bc tree" "extra/bc;touch pwned" "x/\$(touch pwned)" $'\xc4\x87/bc' $'extra/b\xc4\x87'
)

readonly REFUSED_ENTRIES=(
  # Option-like entry
  "--nodeps" "-dd" "--assume-installed=glibc" "-"
  # Shell metacharacters and inner whitespace; the last entry ends in a non-ASCII letter, c with acute, as its UTF-8
  # bytes
  "x;touch /tmp/pwned" "\$(touch /tmp/pwned)" "\`touch /tmp/pwned\`" "bc|touch /tmp/pwned" "bc&&touch /tmp/pwned"
  "b*" "b?" "bc~1" "bc tree" $'bc\ttree' $'bć'
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept. For parallelDownloads:
# outside 1 to 20, a second spelling of an accepted number, whitespace around it, shell text, digits followed by a line
# break and a configuration setting, a non-ASCII digit (Arabic-Indic three), and a digit string too long for a number.
readonly INVALID_CONTROLS=(
  "cleanup CLEANUP=invalid" "cleanup CLEANUP="
  "parallelDownloads PARALLELDOWNLOADS=0" "parallelDownloads PARALLELDOWNLOADS=21"
  "parallelDownloads PARALLELDOWNLOADS=100" "parallelDownloads PARALLELDOWNLOADS=-1"
  "parallelDownloads PARALLELDOWNLOADS=01" "parallelDownloads PARALLELDOWNLOADS=+3"
  "parallelDownloads PARALLELDOWNLOADS= 3" "parallelDownloads PARALLELDOWNLOADS=3 "
  "parallelDownloads PARALLELDOWNLOADS=1.5" "parallelDownloads PARALLELDOWNLOADS=3x"
  "parallelDownloads PARALLELDOWNLOADS=0x3" "parallelDownloads PARALLELDOWNLOADS=five"
  "parallelDownloads PARALLELDOWNLOADS=\$(touch /tmp/pwned)" "parallelDownloads PARALLELDOWNLOADS=3;touch /tmp/pwned"
  $'parallelDownloads PARALLELDOWNLOADS=3\nSigLevel = Never' $'parallelDownloads PARALLELDOWNLOADS=3\n'
  $'parallelDownloads PARALLELDOWNLOADS=\xd9\xa3' "parallelDownloads PARALLELDOWNLOADS=99999999999999999999999"
)

# The entry $1 is refused with status 1 and named, and nothing changed: no sync database was downloaded, no package
# changed, and no command in the entry ran. The valid entry tree runs beside it, so a gap in the validation would
# install something.
refuses_entry() {
  run_install PACKAGES="tree,$1"
  exited_with 1 && refused "$1" && no_sync_databases && local_database_is "${database_before}" && no_command_ran
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2, before
# pacman is called and before a temporary file exists.
refuses_control() {
  run_install_with_stand_in PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}" && pacman_was_called 0 && temporary_files_are "${temporary_before}"
}

# No shell text in a value ran: the values would create /tmp/pwned, or pwned in the directory the runs start in.
no_command_ran() {
  if [[ -e /tmp/pwned || -e pwned ]]; then
    echo "a command in a value ran" >&2
    return 1
  fi
}

database_before="$(local_database)"
configuration_before="$(repository_configuration)"
temporary_before="$(temporary_files)"

for entry in "${REFUSED_PATHS[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
  check "the refusal of '${entry}' says that paths and URLs are not accepted" \
    printed "paths and URLs are not accepted"
done
for entry in "${MALFORMED_QUALIFIERS[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
  check "the refusal of '${entry}' names the repository/target form" \
    printed "malformed repository qualifier; use repository/target"
done
for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

# From here on pacman is a stand-in that records its call and installs nothing.
create_stand_in only

for control in "${INVALID_CONTROLS[@]}"; do
  check "'${control#* }' fails with status 1 and names ${control%% *}, with an empty list" \
    refuses_control "${control}" ""
  check "'${control#* }' fails with status 1 and names ${control%% *}, with the list tree" \
    refuses_control "${control}" "tree"
done

for cleanup in all packages none; do
  run_install_with_stand_in PACKAGES=$' ,\t, ' CLEANUP="${cleanup}" PARALLELDOWNLOADS=7
  check "a list of commas and whitespace succeeds with cleanup=${cleanup} and parallelDownloads=7" exited_with 0
  check "that run does not call pacman" pacman_was_called 0
  check "that run creates no temporary file" temporary_files_are "${temporary_before}"
done

for value in "" 1 20; do
  run_install_with_stand_in PACKAGES="" PARALLELDOWNLOADS="${value}"
  check "parallelDownloads='${value}' is accepted with an empty list" exited_with 0
  check "parallelDownloads='${value}' with an empty list does not call pacman" pacman_was_called 0
  run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS="${value}"
  check "parallelDownloads='${value}' is accepted with the list tree" exited_with 0
  check "parallelDownloads='${value}' with the list tree calls pacman once" pacman_was_called 1
done
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=1
check "with parallelDownloads=1 pacman's configuration resolves ParallelDownloads as 1" resolved_parallel_downloads 1
run_install_with_stand_in PACKAGES=tree PARALLELDOWNLOADS=20
check "with parallelDownloads=20 pacman's configuration resolves ParallelDownloads as 20" \
  resolved_parallel_downloads 20

# Without parallelDownloads and without a qualified entry the call is the one version 1.0.1 made.
run_install_with_stand_in PACKAGES="bc, tree>=1"
check "bc, tree>=1 is accepted" exited_with 0
check "pacman receives the arguments of version 1.0.1 and each entry as one argument" \
  pacman_received "${PACMAN_ARGUMENTS[@]}" "bc" "tree>=1"
check "that run creates no file under /tmp" temporary_files_are "${temporary_before}"

run_install_with_stand_in PACKAGES="extra/bc, core/glibc>=2.0 ,my-repo.x_1+/libsigc++=1:2.0-1,0ad/0ad"
check "repository-qualified entries, with and without a version constraint, are accepted" exited_with 0
check "each qualified entry reaches pacman unchanged as one argument" \
  pacman_received "${PACMAN_ARGUMENTS[@]}" "extra/bc" "core/glibc>=2.0" "my-repo.x_1+/libsigc++=1:2.0-1" "0ad/0ad"

check "no run ran shell text from a value" no_command_ran
check "no run changed an installed package" local_database_is "${database_before}"
check "no run changed the repository configuration" repository_configuration_is "${configuration_before}"
check "no run left a file under /tmp" temporary_files_are "${temporary_before}"

reportResults
