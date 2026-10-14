#!/bin/sh
# Installs the packages listed in the option `packages` with dnf from the repositories the image enables, as the options
# `enableRepositories` and `disableRepositories` adjust them for this one call, to the paths the packages define. Runs
# as root at image build time; the options arrive as PACKAGES, INSTALLWEAKDEPS, REFRESHPOLICY, CLEANUP, NETWORKTIMEOUT,
# BEST, ENABLEREPOSITORIES, DISABLEREPOSITORIES, and PARALLELDOWNLOADS.
# POSIX sh, because an empty list must succeed, and a missing dnf be reported, on images that ship no bash.
set -eu

# The characters an entry may start with and those it may hold, enumerated so that no locale adds a letter to a range.
readonly ENTRY_FIRST_CHARS="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
readonly ENTRY_CHARS="${ENTRY_FIRST_CHARS}._+:~^-"
# The characters a repository identifier may hold, which are those dnf accepts. An identifier starts like an entry, with
# a letter or digit, so none reads as an option.
readonly REPOSITORY_CHARS="${ENTRY_FIRST_CHARS}_.:-"

# A default applies only to an unset option: an explicitly empty installWeakDeps, refreshPolicy, cleanup, or best is
# invalid and reaches validation, while an empty `packages` is the documented no-op and an empty networkTimeout,
# enableRepositories, disableRepositories, or parallelDownloads its default, which leaves the image's setting alone.
PACKAGES="${PACKAGES-}"
INSTALLWEAKDEPS="${INSTALLWEAKDEPS-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"
BEST="${BEST-inherit}"
ENABLEREPOSITORIES="${ENABLEREPOSITORIES-}"
DISABLEREPOSITORIES="${DISABLEREPOSITORIES-}"
PARALLELDOWNLOADS="${PARALLELDOWNLOADS-}"

trimmed=""
identifiers=""
# The identifiers that enableRepositories and disableRepositories name, each once and joined by commas.
enabled_identifiers=""
disabled_identifiers=""
# The identifiers of the repositories the image configures, each followed by a comma, after a leading comma.
configured_identifiers=","

log() {
  printf 'dnf-packages: %s\n' "$*"
}

fail() {
  printf 'dnf-packages: error: %s\n' "$*" >&2
  exit 1
}

# Sets the global trimmed to $1 without leading and trailing whitespace. [[:space:]] follows the locale, so main calls
# it under LC_ALL=C.
trim() {
  trimmed="$1"
  while :; do
    case "${trimmed}" in
      [[:space:]]*) trimmed="${trimmed#?}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "${trimmed}" in
      *[[:space:]]) trimmed="${trimmed%?}" ;;
      *) break ;;
    esac
  done
}

# Fails unless $1 is an entry the spec accepts ("Entries are validated before anything changes").
check_entry() {
  case "$1" in
    [!${ENTRY_FIRST_CHARS}]* | *[!${ENTRY_CHARS}]* | *.[rR][pP][mM])
      fail "refusing the entry '$1': not a package name with an optional version or architecture;" \
        "start with an ASCII letter or digit, use only ASCII letters, digits, and . _ + - : ~ ^, and do not end in .rpm"
      ;;
  esac
}

# Sets the global identifiers to the repository identifiers of the comma-separated list $2, each once and joined by
# commas. Fails, naming the option $1, for an identifier the spec refuses ("Installation controls are validated before
# changes"). main calls it under LC_ALL=C.
collect_identifiers() {
  identifiers=""
  collect_identifiers_rest="$2,"
  while [ -n "${collect_identifiers_rest}" ]; do
    collect_identifiers_item="${collect_identifiers_rest%%,*}"
    collect_identifiers_rest="${collect_identifiers_rest#*,}"
    trim "${collect_identifiers_item}"
    if [ -z "${trimmed}" ]; then continue; fi
    case "${trimmed}" in
      [!${ENTRY_FIRST_CHARS}]* | *[!${REPOSITORY_CHARS}]*)
        fail "option $1 holds '${trimmed}', which is not a repository identifier; start with an ASCII letter or" \
          "digit and use only ASCII letters, digits, and _ . : - (a pattern, a path, and an option are refused)"
        ;;
    esac
    case ",${identifiers}," in
      *",${trimmed},"*) ;;
      *) identifiers="${identifiers:+${identifiers},}${trimmed}" ;;
    esac
  done
}

validate_options() {
  case "${INSTALLWEAKDEPS}" in
    true | false) ;;
    *) fail "option installWeakDeps is \"${INSTALLWEAKDEPS}\"; use true or false" ;;
  esac
  case "${REFRESHPOLICY}" in
    default | always | never) ;;
    *) fail "option refreshPolicy is \"${REFRESHPOLICY}\"; use default, always, or never" ;;
  esac
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  validate_options_hint="leave it empty or use whole seconds from 1 through 3600 without a leading zero"
  if [ -n "${NETWORKTIMEOUT}" ]; then
    case "${NETWORKTIMEOUT}" in
      0* | *[!0123456789]*) fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_options_hint}" ;;
    esac
    # The length is tested first, so a value of many digits never reaches integer arithmetic.
    if [ "${#NETWORKTIMEOUT}" -gt 4 ] || [ "${NETWORKTIMEOUT}" -gt 3600 ]; then
      fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_options_hint}"
    fi
  fi
  case "${BEST}" in
    inherit | true | false) ;;
    *) fail "option best is \"${BEST}\"; use inherit, true, or false" ;;
  esac
  # dnf accepts values such as 21, -1, and 05 when it parses its options and fails later, so the range is checked here.
  validate_options_hint="leave it empty or use a whole number from 1 through 20 without a leading zero"
  if [ -n "${PARALLELDOWNLOADS}" ]; then
    case "${PARALLELDOWNLOADS}" in
      0* | *[!0123456789]*) fail "option parallelDownloads is \"${PARALLELDOWNLOADS}\"; ${validate_options_hint}" ;;
    esac
    # The length is tested first, so a value of many digits never reaches integer arithmetic.
    if [ "${#PARALLELDOWNLOADS}" -gt 2 ] || [ "${PARALLELDOWNLOADS}" -gt 20 ]; then
      fail "option parallelDownloads is \"${PARALLELDOWNLOADS}\"; ${validate_options_hint}"
    fi
  fi
  collect_identifiers enableRepositories "${ENABLEREPOSITORIES}"
  enabled_identifiers="${identifiers}"
  collect_identifiers disableRepositories "${DISABLEREPOSITORIES}"
  disabled_identifiers="${identifiers}"
  # dnf lets the later of --enablerepo and --disablerepo win, so an identifier in both lists has no meaning of its own.
  validate_options_rest="${enabled_identifiers:+${enabled_identifiers},}"
  while [ -n "${validate_options_rest}" ]; do
    validate_options_identifier="${validate_options_rest%%,*}"
    validate_options_rest="${validate_options_rest#*,}"
    case ",${disabled_identifiers}," in
      *",${validate_options_identifier},"*)
        fail "options enableRepositories and disableRepositories both hold '${validate_options_identifier}';" \
          "name a repository in one of the two only"
        ;;
    esac
  done
  readonly INSTALLWEAKDEPS REFRESHPOLICY CLEANUP NETWORKTIMEOUT
  readonly BEST ENABLEREPOSITORIES DISABLEREPOSITORIES PARALLELDOWNLOADS
}

# Fails, naming the image's distribution, unless dnf is on PATH.
require_dnf() {
  if command -v dnf >/dev/null 2>&1; then return 0; fi
  require_dnf_distribution=""
  if [ -r /etc/os-release ]; then
    # A malformed /etc/os-release, or one that assigns a readonly name, fails the subshell. The message below must
    # still be the one that ends the run, so the distribution then stays unidentified.
    # shellcheck source=/dev/null
    if ! require_dnf_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"; then
      require_dnf_distribution=""
    fi
  fi
  fail "dnf was not found on this image (${require_dnf_distribution:-an unidentified distribution});" \
    "use a Fedora or RHEL-compatible image, which provides dnf (images with only microdnf are not supported)"
}

# Fails, naming the option $1, unless the image configures every repository of the comma-joined identifiers $2.
check_configured() {
  check_configured_rest="${2:+$2,}"
  while [ -n "${check_configured_rest}" ]; do
    check_configured_identifier="${check_configured_rest%%,*}"
    check_configured_rest="${check_configured_rest#*,}"
    case "${configured_identifiers}" in
      *",${check_configured_identifier},"*) ;;
      *)
        fail "option $1 names the repository '${check_configured_identifier}', which this image does not configure;" \
          "use an identifier that \"dnf repolist --all\" prints, in the same letter case"
        ;;
    esac
  done
}

# Fails unless the image configures every repository the two repository options name. dnf 4 only warns about an
# unknown --disablerepo and goes on, so the feature compares the identifiers itself, exactly, with dnf's own listing.
# The listing loads no repository metadata and needs no network.
require_configured_repositories() {
  if [ -z "${enabled_identifiers}${disabled_identifiers}" ]; then return 0; fi
  log "reading the repositories the image configures from dnf repolist --all"
  require_configured_repositories_listing="$(dnf -q repolist --all)" \
    || fail "dnf repolist failed with status $?, so the repositories in enableRepositories and disableRepositories" \
      "cannot be checked; fix what dnf reports above"
  # The listing is one header line and then one row per repository, whose first field is the identifier.
  require_configured_repositories_header=yes
  while read -r require_configured_repositories_identifier _; do
    if [ -n "${require_configured_repositories_header}" ]; then
      require_configured_repositories_header=""
      continue
    fi
    configured_identifiers="${configured_identifiers}${require_configured_repositories_identifier},"
  done <<EOF
${require_configured_repositories_listing}
EOF
  check_configured enableRepositories "${enabled_identifiers}"
  check_configured disableRepositories "${disabled_identifiers}"
}

# Installs the entries in "$@" with one dnf call. Every setting is an argument of that call, so the image's dnf
# configuration stays unchanged.
install_packages() {
  install_packages_source="the image's enabled repositories"
  if [ -n "${disabled_identifiers}" ]; then
    install_packages_source="${install_packages_source} without ${disabled_identifiers}"
  fi
  if [ -n "${enabled_identifiers}" ]; then
    install_packages_source="${install_packages_source} and from ${enabled_identifiers}"
  fi
  install_packages_controls="installWeakDeps=${INSTALLWEAKDEPS}, refreshPolicy=${REFRESHPOLICY}"
  if [ "${BEST}" != inherit ]; then
    install_packages_controls="${install_packages_controls}, best=${BEST}"
  fi
  if [ -n "${PARALLELDOWNLOADS}" ]; then
    install_packages_controls="${install_packages_controls}, parallelDownloads=${PARALLELDOWNLOADS}"
  fi
  log "installing $* from ${install_packages_source} (${install_packages_controls})"
  # POSIX sh has no arrays, so dnf's arguments are prepended to the positional parameters, the entries after `--`.
  set -- -- "$@"
  case "${REFRESHPOLICY}" in
    always) set -- --refresh '--setopt=*.skip_if_unavailable=False' "$@" ;;
    never) set -- --cacheonly '--setopt=*.skip_if_unavailable=False' "$@" ;;
    default) ;;
  esac
  if [ -n "${NETWORKTIMEOUT}" ]; then
    set -- "--setopt=timeout=${NETWORKTIMEOUT}" "--setopt=*.timeout=${NETWORKTIMEOUT}" "$@"
  fi
  # A repository's own max_parallel_downloads wins over the main one, so the bound is set for both.
  if [ -n "${PARALLELDOWNLOADS}" ]; then
    set -- "--setopt=max_parallel_downloads=${PARALLELDOWNLOADS}" \
      "--setopt=*.max_parallel_downloads=${PARALLELDOWNLOADS}" "$@"
  fi
  case "${BEST}" in
    true) set -- --setopt=best=True "$@" ;;
    false) set -- --setopt=best=False "$@" ;;
    inherit) ;;
  esac
  # One argument per identifier, so dnf splits no list and expands no pattern. The enable arguments are prepended
  # first: every --disablerepo then precedes every --enablerepo.
  install_packages_rest="${enabled_identifiers:+${enabled_identifiers},}"
  while [ -n "${install_packages_rest}" ]; do
    set -- "--enablerepo=${install_packages_rest%%,*}" "$@"
    install_packages_rest="${install_packages_rest#*,}"
  done
  install_packages_rest="${disabled_identifiers:+${disabled_identifiers},}"
  while [ -n "${install_packages_rest}" ]; do
    set -- "--disablerepo=${install_packages_rest%%,*}" "$@"
    install_packages_rest="${install_packages_rest#*,}"
  done
  case "${INSTALLWEAKDEPS}" in
    true) install_packages_weak_deps=True ;;
    false) install_packages_weak_deps=False ;;
  esac
  dnf install --assumeyes "--setopt=install_weak_deps=${install_packages_weak_deps}" "$@" \
    || fail "dnf install failed with status $?; fix what dnf reports above (entries, repositories, or network)"
}

# Cleans dnf's effective cache as the option cleanup selects.
clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages and the repository metadata from dnf's cache (cleanup=all)"
      dnf clean all || fail "dnf clean failed with status $?; fix what dnf reports above, or use cleanup=none"
      ;;
    packages)
      log "removing downloaded packages from dnf's cache (cleanup=packages)"
      dnf clean packages || fail "dnf clean failed with status $?; fix what dnf reports above, or use cleanup=none"
      ;;
    none) ;;
  esac
}

main() {
  # The options and the list are checked under LC_ALL=C: trim's [[:space:]] follows the locale, and no locale may add
  # a character to the enumerated sets. The image's locale is back before dnf runs.
  main_locale_was_set="${LC_ALL+yes}"
  main_locale_before="${LC_ALL-}"
  LC_ALL=C
  validate_options

  # Collects the accepted entries as main's positional parameters, discarding the script's own arguments.
  set --
  main_rest="${PACKAGES},"
  while [ -n "${main_rest}" ]; do
    main_entry="${main_rest%%,*}"
    main_rest="${main_rest#*,}"
    trim "${main_entry}"
    if [ -z "${trimmed}" ]; then continue; fi
    check_entry "${trimmed}"
    set -- "$@" "${trimmed}"
  done
  if [ -n "${main_locale_was_set}" ]; then
    LC_ALL="${main_locale_before}"
  else
    unset LC_ALL
  fi
  readonly PACKAGES

  if [ "$#" -eq 0 ]; then
    log "no packages listed; nothing to do"
    exit 0
  fi
  # dnf is required only from here on: the spec lets an empty list succeed on an image without dnf ("Option packages"),
  # and without a check of the repository options against the image ("Repository selection is scoped to installation").
  require_dnf
  require_configured_repositories
  install_packages "$@"
  clean_caches
}

main "$@"
