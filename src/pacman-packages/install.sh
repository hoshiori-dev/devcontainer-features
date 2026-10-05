#!/bin/sh
# Installs the packages listed in the option `packages` with pacman from the image's repositories, as part of a full
# system upgrade, to the paths the packages define.
# Runs as root at image build time; the options arrive as PACKAGES, CLEANUP.
# POSIX sh, because an empty list must succeed, and a missing pacman be reported, on images that ship no bash.
set -eu

readonly PACKAGE_CACHE_DIR="/var/cache/pacman/pkg"
readonly SYNC_DB_DIR="/var/lib/pacman/sync"

PACKAGES="${PACKAGES-}"
CLEANUP="${CLEANUP-all}"

trimmed=""

log() {
  printf 'pacman-packages: %s\n' "$*"
}

fail() {
  printf 'pacman-packages: error: %s\n' "$*" >&2
  exit 1
}

validate_options() {
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  readonly CLEANUP
}

# Sets trimmed to $1 without its leading and trailing whitespace.
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

# Fails unless the entry $1 matches ^[A-Za-z0-9][A-Za-z0-9@._+:<>=-]*$. The character sets are spelled out instead of
# written as ranges, which some shells read by locale collation.
check_entry() {
  case "$1" in
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | \
      *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+:\<\>=-]*)
      fail "refusing the entry '$1': not a package, provided, or group name with an optional version constraint;" \
        "start with an ASCII letter or digit and use only ASCII letters, digits, and @ . _ + - : < > ="
      ;;
  esac
}

# Fails unless pacman is on PATH, naming the distribution /etc/os-release describes.
check_pacman() {
  if command -v pacman >/dev/null 2>&1; then return 0; fi
  check_pacman_distribution=""
  if [ -r /etc/os-release ]; then
    # A file that fails to source leaves the fallback text instead of ending the script without the pacman message.
    # shellcheck source=/dev/null
    check_pacman_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")" \
      || check_pacman_distribution=""
  fi
  if [ -z "${check_pacman_distribution}" ]; then check_pacman_distribution="an unidentified distribution"; fi
  fail "pacman was not found on this image (${check_pacman_distribution});" \
    "use an Arch Linux image, which provides pacman"
}

# Installs the entries given as arguments in one transaction that also synchronizes every database and upgrades the
# system (Arch Linux supports no partial upgrade). --needed skips a listed package that is already up to date, and
# --noconfirm takes pacman's default answer to every question.
install_packages() {
  log "upgrading the system and installing $* from the image's repositories"
  pacman --sync --refresh --sysupgrade --needed --noconfirm -- "$@" \
    || fail "pacman --sync failed with status $?;" \
      "fix what pacman reports above (entries, mirrors, keyring, or network)"
}

# Empties the cache directories that CLEANUP selects. They are deleted directly: `pacman --sync --clean --clean` asks
# before it removes, and under --noconfirm the answer is no. `:?` stops rm if a path constant were ever empty.
clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages from ${PACKAGE_CACHE_DIR} and the sync databases from ${SYNC_DB_DIR}" \
        "(cleanup=all)"
      rm --recursive --force "${PACKAGE_CACHE_DIR:?}"/* "${SYNC_DB_DIR:?}"/*
      ;;
    packages)
      log "removing downloaded packages from ${PACKAGE_CACHE_DIR} (cleanup=packages)"
      rm --recursive --force "${PACKAGE_CACHE_DIR:?}"/*
      ;;
    none) ;;
  esac
}

main() {
  validate_options

  # Every entry is checked before anything else happens, and the accepted entries become main's positional parameters,
  # so each reaches pacman as one argument and none is evaluated as shell code. The check runs in the C locale, where a
  # bracket expression matches single bytes and so no non-ASCII letter; the locale the build set is restored
  # afterwards, so pacman and the packages' install scripts run in it.
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
  check_pacman
  install_packages "$@"
  clean_caches
}

main "$@"
