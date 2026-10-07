#!/usr/bin/env bash
# Scenario test_entry_forms (scenarios.json): the feature is installed with an empty list, and this script then runs
# install.sh with lists that install, whose entries it chooses from the repositories when it runs. Spec scenarios
# "Satisfied constraint is installed", "Installation runs without a terminal", "Name with several providers installs the
# first", and "Group name installs the whole group".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The repositories' package names as "N <name>" and provided names, without their versions, as
# "P <provided name> <providing package>": what repository_names prints.
readonly NAMES_FILE="/tmp/repository-names"

# Prints the lines of NAMES_FILE. Needs sync databases.
repository_names() {
  pacman -Si | awk '
    $1 == "Name" && $2 == ":" { name = $3; print "N", name }
    $1 == "Provides" && $2 == ":" {
      for (i = 3; i <= NF; i++) {
        provided = $i
        sub(/[<>=].*$/, "", provided)
        if (provided != "None" && provided != "") print "P", provided, name
      }
    }'
}

# Prints the packages pacman would install for the target $1 as "<name> <download size>"; fails when pacman refuses it.
resolution() {
  pacman -Sp --print-format '%n %s' --noconfirm -- "$1" 2>/dev/null
}

# The resolution $1 holds the package $2.
resolution_holds() {
  awk -v name="$2" '$1 == name { found = 1 } END { exit !found }' <<<"$1"
}

# Prints "<name> <chosen provider> <other providers>…" for a name that no package has and several packages provide,
# none of them installed, with the one provider pacman itself chooses for it. cron first: two small providers; the
# others in order, the first of forty that resolves to one provider and at most twelve packages. Chosen when the test
# runs, because provided names come and go. Needs NAMES_FILE.
provided_name() {
  local installed_names candidates name providers provider resolved chosen others
  installed_names="$(pacman -Qq)"
  candidates="$(awk '
    $1 == "N" { names[$2] = 1 }
    $1 == "P" && !seen[$2, $3]++ { providers[$2] = providers[$2] " " $3; count[$2]++ }
    END {
      for (provided in providers) {
        if (!(provided in names) && provided !~ /\.so/ && count[provided] > 1) print provided providers[provided]
      }
    }' "${NAMES_FILE}" | sort)"
  while read -r name providers; do
    for provider in ${providers}; do
      if grep --line-regexp --fixed-strings --quiet -- "${provider}" <<<"${installed_names}"; then continue 2; fi
    done
    if ! resolved="$(resolution "${name}")"; then continue; fi
    if [[ "$(wc -l <<<"${resolved}")" -gt 12 ]]; then continue; fi
    chosen=""
    others=""
    for provider in ${providers}; do
      if resolution_holds "${resolved}" "${provider}"; then
        chosen+=" ${provider}"
      else
        others+=" ${provider}"
      fi
    done
    if [[ "$(wc -w <<<"${chosen}")" -ne 1 ]]; then continue; fi
    echo "${name}${chosen}${others}"
    return 0
  done < <({
    grep '^cron ' <<<"${candidates}" || true
    grep --invert-match '^cron ' <<<"${candidates}"
  } | awk 'NR <= 40')
  echo "no provided name with several providers resolves to one small provider" >&2
  return 1
}

# Prints "<group> <members>…" for the package group with the smallest download among those of two to four members,
# none installed, whose name is no package and no provided name. Chosen when the test runs, because groups come and go.
# Needs sync databases and NAMES_FILE.
small_group() {
  local installed_names group members member resolved size best="" best_size=""
  installed_names="$(pacman -Qq)"
  while read -r group members; do
    if awk -v name="${group}" '$2 == name { found = 1 } END { exit !found }' "${NAMES_FILE}"; then continue; fi
    if ! resolved="$(resolution "${group}")"; then continue; fi
    for member in ${members}; do
      if grep --line-regexp --fixed-strings --quiet -- "${member}" <<<"${installed_names}"; then continue 2; fi
      if ! resolution_holds "${resolved}" "${member}"; then continue 2; fi
    done
    size="$(awk '{ sum += $2 } END { print sum }' <<<"${resolved}")"
    if [[ -z "${best}" || "${size}" -lt "${best_size}" ]]; then
      best="${group} ${members}"
      best_size="${size}"
    fi
  done < <(pacman -Sgg | awk '
    { members[$1] = members[$1] " " $2; count[$1]++ }
    END { for (group in members) if (count[group] >= 2 && count[group] <= 4) print group members[group] }' | sort)
  if [[ -z "${best}" ]]; then
    echo "no small package group is offered" >&2
    return 1
  fi
  echo "${best}"
}

# Runs install.sh with the list $1, without a terminal and with no input, and prints its output; a run that waited for
# input would end with timeout's status 124.
run_install_without_terminal() {
  install_status=0
  # The inner sh expands $1, the installer's path; and exited_with in installer.sh reads install_status.
  # shellcheck disable=SC2016,SC2034
  install_output="$(env PACKAGES="$1" sh -c 'test ! -t 0 && test ! -t 1 && exec timeout 900 "$1"' \
    sh "${INSTALLER}" </dev/null 2>&1)" || install_status=$?
  printf '%s\n' "${install_output}"
}

every_one_installed() {
  local package
  for package in "$@"; do
    installed "${package}" || return
  done
}

none_installed() {
  local package
  for package in "$@"; do
    not_installed "${package}" || return
  done
}

# The versions the repositories offer when the test runs: no fixed version stays in a rolling release.
download_sync_databases
bc_version="$(offered_version bc)"
tree_version="$(offered_version tree)"
remove_caches
# name=<offered pkgver>, without the pkgrel, and name>=<offered version>.
entries="bc=${bc_version%-*},tree>=${tree_version}"
run_install PACKAGES="${entries}"
check "${entries} (constraints the offered versions satisfy) installs" exited_with 0
check "bc is installed at the offered version ${bc_version}" has_version bc "${bc_version}"
check "tree is installed at the offered version ${tree_version}" has_version tree "${tree_version}"

# jq and its dependency oniguruma are not installed, so the run has a transaction to confirm.
check "premise: jq is not installed" not_installed jq
run_install_without_terminal jq
check "jq installs with no terminal and no input, without waiting for input" exited_with 0
check "jq is installed" installed jq

download_sync_databases
repository_names >"${NAMES_FILE}"
selection="$(provided_name)"
read -r name chosen others <<<"${selection}"
remove_caches
run_install PACKAGES="${name}"
check "${name} (pacman chooses ${chosen}; also provided by ${others}) installs" exited_with 0
check "the provider pacman offers first, ${chosen}, is installed" installed "${chosen}"
# The providers are separate arguments.
# shellcheck disable=SC2086
check "no other provider (${others}) is installed" none_installed ${others}

download_sync_databases
selection="$(small_group)"
read -r group members <<<"${selection}"
remove_caches
run_install PACKAGES="${group}"
check "${group} (a package group of ${members}) installs" exited_with 0
# The members are separate arguments.
# shellcheck disable=SC2086
check "every package of the group ${group} is installed" every_one_installed ${members}

reportResults
