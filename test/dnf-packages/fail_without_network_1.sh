#!/usr/bin/env bash
# Scenario fail_without_network_1 (scenarios.json): the feature is installed with an empty list, the container has no
# network, and this script then runs install.sh with input that validation refuses, with dnf hidden from PATH, with
# repository identifiers the image does not configure, and with refreshPolicy=never while the image holds no repository
# metadata. Spec scenarios "URL or path is refused", "Package file name is refused", "Option-like entry is refused",
# "Group, module, and dependency expressions are refused", "Shell metacharacters, globs, and inner whitespace are
# refused", "Invalid control fails before any change", "Empty list ignores installation controls", "Timeout boundaries
# are validated", "Parallel download boundaries are validated", "Best policy values are validated", "Repository
# identifiers are validated", "Identifier in both repository lists is refused", "Empty list is a no-op" and "Image
# without dnf fails clearly" (both with a PATH that holds no dnf), "Unknown repository fails before installation",
# "Identifier in another letter case is unknown", "Repository list cannot be read", and "Missing cached metadata fails
# without refresh".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly REFUSED_ENTRIES=(
  # URL or path
  "/tmp/bc.rpm" "https://example.invalid/bc"
  # Package file name
  "bc.rpm" "bc.RPM"
  # Option-like entry
  "--help"
  # Group, module, and dependency expressions
  "@core" "module:stream/profile" "bc>=1" "(bc)"
  # Shell metacharacters, globs, and inner whitespace
  "bc file" "bc;echo bad" "b*" "évil"
)

# Each entry is "<option> <environment assignment>" with a value the option does not accept.
readonly INVALID_CONTROLS=(
  "cleanup CLEANUP=invalid" "cleanup CLEANUP="
  "refreshPolicy REFRESHPOLICY=invalid" "refreshPolicy REFRESHPOLICY="
  "installWeakDeps INSTALLWEAKDEPS=yes" "installWeakDeps INSTALLWEAKDEPS="
  "networkTimeout NETWORKTIMEOUT=0" "networkTimeout NETWORKTIMEOUT=3601" "networkTimeout NETWORKTIMEOUT=01"
  "networkTimeout NETWORKTIMEOUT=-1" "networkTimeout NETWORKTIMEOUT=+1" "networkTimeout NETWORKTIMEOUT=1 "
  "networkTimeout NETWORKTIMEOUT=1.5" "networkTimeout NETWORKTIMEOUT=１２"
  "networkTimeout NETWORKTIMEOUT=\$(touch /tmp/pwned)" "networkTimeout NETWORKTIMEOUT=999999999999999999999999"
  "best BEST=" "best BEST=yes" "best BEST=True" "best BEST=INHERIT" "best BEST=\$(touch /tmp/pwned)"
  "parallelDownloads PARALLELDOWNLOADS=0" "parallelDownloads PARALLELDOWNLOADS=21"
  "parallelDownloads PARALLELDOWNLOADS=05" "parallelDownloads PARALLELDOWNLOADS=-1"
  "parallelDownloads PARALLELDOWNLOADS=+1" "parallelDownloads PARALLELDOWNLOADS=2 "
  "parallelDownloads PARALLELDOWNLOADS=1.5" "parallelDownloads PARALLELDOWNLOADS=１２"
  "parallelDownloads PARALLELDOWNLOADS=\$(touch /tmp/pwned)"
  "parallelDownloads PARALLELDOWNLOADS=999999999999999999999999"
)

# Identifiers that neither repository list accepts: a pattern, a leading "-", a "/", a "=", inner whitespace, a
# non-ASCII letter, shell text, and a first character other than a letter or digit.
readonly REFUSED_IDENTIFIERS=(
  "crb*" "[a-z]" "-crb" "--help" "a/b" "a=b" "a b" "évil" "x;touch /tmp/pwned" "\$(touch /tmp/pwned)" "_crb" ".crb"
)

# An identifier of no repository the image configures, and a configured one in another letter case.
readonly UNKNOWN_REPOSITORY="not-configured"
readonly OTHER_CASE_REPOSITORY="BASEOS"
# A repository file whose repository has the identifier "repo", the first word of the header line of dnf's listing.
readonly HEADER_WORD_REPOSITORY="/etc/yum.repos.d/repo.repo"

# A PATH on which dnf is a stub that records its call: a run that reaches the package manager leaves
# /tmp/manager-called.
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"
# A PATH that holds sed and tr and no dnf.
readonly NO_DNF_PATH="/tmp/no-manager"
# A PATH on which dnf fails to list the repositories and records every other call in /tmp/manager-called.
readonly UNREADABLE_PATH="/tmp/unreadable:/usr/sbin:/usr/bin:/sbin:/bin"

# The entry $1 is refused with status 1 and named, and nothing changed: no metadata was loaded and no package changed.
# The valid entry file runs beside it, so a gap in the validation would install something.
refuses_entry() {
  run_install PACKAGES="file,$1"
  exited_with 1 && printed "$1" && no_metadata && rpm_database_is "${database_before}"
}

# The control "<option> <assignment>" in $1 fails with status 1, naming the option, with the package list $2.
refuses_control() {
  run_install PATH="${STUB_PATH}" PACKAGES="$2" "${1#* }"
  exited_with 1 && printed "${1%% *}"
}

# The identifier $3 in the option $1, which arrives as the variable $2, fails with status 1, naming the option and the
# identifier, with the package list $4. The valid identifier baseos runs beside it.
refuses_identifier() {
  run_install PATH="${STUB_PATH}" PACKAGES="$4" "$2=baseos,$3"
  exited_with 1 && printed "option $1" && printed "'$3'"
}

# The identifier $3 in the option $1, which arrives as the variable $2, fails the list bc with status 1 as a repository
# the image does not configure, naming the option and the identifier, before dnf loads metadata or changes a package.
refuses_unconfigured() {
  run_install PACKAGES=bc "$2=$3"
  exited_with 1 && printed "option $1 names the repository '$3'" && no_metadata && rpm_database_is "${database_before}"
}

# dnf and the other package managers print one of these texts when they fetch repository metadata.
attempted_no_download() {
  if output_matches 'fetch https?:|Downloading|Retrieving repository'; then
    echo "dnf tried to fetch metadata" >&2
    return 1
  fi
}

# Neither the package manager nor shell text in a value ran.
nothing_ran() {
  if [[ -e /tmp/manager-called || -e /tmp/pwned ]]; then
    echo "dnf was called, or a command in a value ran" >&2
    return 1
  fi
}

database_before="$(rpm_database)"
configuration_before="$(dnf_configuration)"

for entry in "${REFUSED_ENTRIES[@]}"; do
  check "the entry '${entry}' is refused with status 1 before anything changes" refuses_entry "${entry}"
done

mkdir /tmp/stub
printf '#!/bin/sh\necho called >>/tmp/manager-called\nexit 0\n' >/tmp/stub/dnf
chmod +x /tmp/stub/dnf

for control in "${INVALID_CONTROLS[@]}"; do
  check "'${control#* }' fails with status 1 and names ${control%% *}, with an empty list" \
    refuses_control "${control}" ""
  check "'${control#* }' fails with status 1 and names ${control%% *}, with the list bc" \
    refuses_control "${control}" "bc"
done

for identifier in "${REFUSED_IDENTIFIERS[@]}"; do
  for packages in "" bc; do
    check "enableRepositories refuses the identifier '${identifier}' with status 1, with the list '${packages}'" \
      refuses_identifier enableRepositories ENABLEREPOSITORIES "${identifier}" "${packages}"
    check "disableRepositories refuses the identifier '${identifier}' with status 1, with the list '${packages}'" \
      refuses_identifier disableRepositories DISABLEREPOSITORIES "${identifier}" "${packages}"
  done
done

for packages in "" bc; do
  run_install PATH="${STUB_PATH}" PACKAGES="${packages}" ENABLEREPOSITORIES="crb,extras" DISABLEREPOSITORIES=" extras "
  check "an identifier in both repository lists fails with status 1, with the list '${packages}'" exited_with 1
  check "the message names the identifier that both lists hold, with the list '${packages}'" printed "'extras'"
done

for cleanup in all packages none; do
  run_install PATH="${STUB_PATH}" PACKAGES=$' ,\t, ' CLEANUP="${cleanup}"
  check "a list of commas and whitespace succeeds with cleanup=${cleanup}" exited_with 0
done
for timeout in "" 1 3600; do
  run_install PATH="${STUB_PATH}" PACKAGES="" NETWORKTIMEOUT="${timeout}"
  check "an empty list succeeds with networkTimeout='${timeout}'" exited_with 0
done
for downloads in "" 1 20; do
  run_install PATH="${STUB_PATH}" PACKAGES="" PARALLELDOWNLOADS="${downloads}"
  check "an empty list succeeds with parallelDownloads='${downloads}'" exited_with 0
done
for best in inherit true false; do
  run_install PATH="${STUB_PATH}" PACKAGES="" BEST="${best}"
  check "an empty list succeeds with best=${best}" exited_with 0
done
run_install PATH="${STUB_PATH}" PACKAGES="" BEST=true PARALLELDOWNLOADS=20 \
  ENABLEREPOSITORIES="${UNKNOWN_REPOSITORY}" DISABLEREPOSITORIES=" A-b_c.d:e ,, 9 "
check "an empty list succeeds with repository identifiers the image does not configure" exited_with 0

check "no run called dnf or ran shell text from a value" nothing_ran
check "no run loaded repository metadata" no_metadata
check "no run changed an installed package" rpm_database_is "${database_before}"
check "no run changed the dnf configuration" dnf_configuration_is "${configuration_before}"

mkdir "${NO_DNF_PATH}"
for tool in sed tr; do
  ln -s "$(command -v "${tool}")" "${NO_DNF_PATH}/${tool}"
done

run_install PATH="${NO_DNF_PATH}" PACKAGES=""
check "without dnf on PATH an empty list exits with status 0" exited_with 0
run_install PATH="${NO_DNF_PATH}" PACKAGES="" BEST=false PARALLELDOWNLOADS=1 ENABLEREPOSITORIES="${UNKNOWN_REPOSITORY}"
check "without dnf on PATH an empty list with valid repository and solver controls exits with status 0" exited_with 0
run_install PATH="${NO_DNF_PATH}" PACKAGES=bc
check "without dnf on PATH the list bc exits with status 1" exited_with 1
check "the message says that dnf was not found" printed "dnf was not found"
check "the message names Fedora and RHEL-compatible images" printed "Fedora or RHEL-compatible"
check "the runs without dnf on PATH changed no installed package" rpm_database_is "${database_before}"
check "the runs without dnf on PATH changed no dnf configuration" dnf_configuration_is "${configuration_before}"

# The image's dnf lists the configured repositories without a network. No repository of the image has the identifier
# "repo", so the header line of the listing must not count as one.
for identifier in "${UNKNOWN_REPOSITORY}" "${OTHER_CASE_REPOSITORY}" repo; do
  check "enableRepositories=${identifier} fails with status 1 before dnf loads metadata or changes a package" \
    refuses_unconfigured enableRepositories ENABLEREPOSITORIES "${identifier}"
  check "disableRepositories=${identifier} fails with status 1 before dnf loads metadata or changes a package" \
    refuses_unconfigured disableRepositories DISABLEREPOSITORIES "${identifier}"
done
check "the runs with unconfigured identifiers left the dnf configuration unchanged" \
  dnf_configuration_is "${configuration_before}"

# With a repository of that identifier in the image, the same value passes the check and the run goes on to dnf, which
# fails for lack of cached metadata.
printf '%s\n' "[repo]" "name=repo" "baseurl=http://127.0.0.1:9/" "enabled=0" >"${HEADER_WORD_REPOSITORY}"
run_install PACKAGES=bc DISABLEREPOSITORIES=repo REFRESHPOLICY=never CLEANUP=none
check "a configured repository with the identifier repo is found in the listing" \
  printed "installing bc from the image's enabled repositories without repo"
rm "${HEADER_WORD_REPOSITORY}"

mkdir "${UNREADABLE_PATH%%:*}"
cat >"${UNREADABLE_PATH%%:*}/dnf" <<'EOF'
#!/bin/sh
case " $* " in
  *" repolist "*)
    echo "the repositories cannot be listed" >&2
    exit 3
    ;;
esac
echo called >>/tmp/manager-called
EOF
chmod +x "${UNREADABLE_PATH%%:*}/dnf"
run_install PATH="${UNREADABLE_PATH}" PACKAGES=bc DISABLEREPOSITORIES=baseos
check "a dnf that cannot list the repositories fails the feature with status 1" exited_with 1
check "the message says that the repositories could not be listed" printed "dnf repolist failed with status 3"
check "after the failed listing dnf is not called to install" nothing_ran

# The runs above left the image without repository metadata, and nothing can be downloaded.
check "premise: the image holds no repository metadata" no_metadata
run_install PACKAGES=bc REFRESHPOLICY=never CLEANUP=packages
check "refreshPolicy=never without cached metadata exits with a non-zero status" failed
check "refreshPolicy=never without cached metadata attempts no download" attempted_no_download
check "refreshPolicy=never without cached metadata does not install bc" not_installed bc
check "refreshPolicy=never without cached metadata changes no installed package" rpm_database_is "${database_before}"
check "refreshPolicy=never without cached metadata leaves the dnf configuration unchanged" \
  dnf_configuration_is "${configuration_before}"

reportResults
