#!/bin/sh
# Installs the packages listed in the option `packages` with dnf from the image's enabled repositories, to the paths the
# packages define. Runs as root at image build time; the options arrive as PACKAGES, INSTALLWEAKDEPS, REFRESHPOLICY,
# CLEANUP, and NETWORKTIMEOUT.
# POSIX sh, because an empty list must succeed, and a missing dnf be reported, on images that ship no bash.
set -eu

# The characters an entry may start with and those it may hold, enumerated so that no locale adds a letter to a range.
readonly ENTRY_FIRST_CHARS="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
readonly ENTRY_CHARS="${ENTRY_FIRST_CHARS}._+:~^-"

# A default applies only to an unset option: an explicitly empty installWeakDeps, refreshPolicy, or cleanup is invalid
# and reaches validation, while an empty `packages` is the documented no-op and an empty networkTimeout its default.
PACKAGES="${PACKAGES-}"
INSTALLWEAKDEPS="${INSTALLWEAKDEPS-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"

trimmed=""

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
  readonly INSTALLWEAKDEPS REFRESHPOLICY CLEANUP NETWORKTIMEOUT
}

# Fails, naming the image's distribution, unless dnf is on PATH.
require_dnf() {
  if command -v dnf >/dev/null 2>&1; then return; fi
  require_dnf_distribution=""
  if [ -r /etc/os-release ]; then
    # Known failure mode: a file that is not valid shell, or that assigns a readonly name, ends the subshell with
    # another status; the message then names no distribution, and the status stays 1.
    # shellcheck source=/dev/null
    require_dnf_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")" || require_dnf_distribution=""
  fi
  fail "dnf was not found on this image (${require_dnf_distribution:-an unidentified distribution});" \
    "use a Fedora or RHEL-compatible image, which provides dnf (images with only microdnf are not supported)"
}

# Installs the entries in "$@" with one dnf call. Every setting is an argument of that call, so the image's dnf
# configuration stays unchanged.
install_packages() {
  log "installing $* from the image's enabled repositories" \
    "(installWeakDeps=${INSTALLWEAKDEPS}, refreshPolicy=${REFRESHPOLICY})"
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
  validate_options

  # Collects the accepted entries as main's positional parameters, discarding the script's own arguments. trim's
  # [[:space:]] follows the locale, so the list is split under LC_ALL=C; the image's locale is back before dnf runs.
  main_locale_was_set="${LC_ALL+yes}"
  main_locale_before="${LC_ALL-}"
  LC_ALL=C
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
  # dnf is required only from here on: the spec lets an empty list succeed on an image without dnf ("Option packages").
  require_dnf
  install_packages "$@"
  clean_caches
}

main "$@"
