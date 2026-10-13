#!/bin/sh
# Installs the packages listed in the option `packages` with pacman from the image's repositories, as part of a full
# system upgrade, to the paths the packages define. A non-empty `parallelDownloads` reaches that one pacman call through
# a temporary configuration file that includes the image's /etc/pacman.conf and is removed when the script exits.
# Runs as root at image build time; the options arrive as PACKAGES, CLEANUP, and PARALLELDOWNLOADS.
# POSIX sh, because an empty list must succeed, and a missing pacman be reported, on images that ship no bash.
set -eu

readonly PACKAGE_CACHE_DIR="/var/cache/pacman/pkg"
readonly SYNC_DB_DIR="/var/lib/pacman/sync"
# The configuration pacman reads by default on Arch Linux. The temporary configuration includes it; nothing changes it.
readonly IMAGE_CONFIGURATION="/etc/pacman.conf"
# The mktemp template of the temporary configuration, outside /etc.
readonly TEMPORARY_CONFIGURATION_TEMPLATE="/tmp/pacman-packages.XXXXXXXX"

PACKAGES="${PACKAGES-}"
CLEANUP="${CLEANUP-all}"
PARALLELDOWNLOADS="${PARALLELDOWNLOADS-}"

trimmed=""
# The path of the temporary configuration once it exists; the exit trap reads it.
temporary_configuration=""

log() {
  printf 'pacman-packages: %s\n' "$*"
}

fail() {
  printf 'pacman-packages: error: %s\n' "$*" >&2
  exit 1
}

# Fails unless CLEANUP is a declared value and PARALLELDOWNLOADS is empty or a decimal integer from 1 through 20 in its
# one spelling: no sign, whitespace, leading zero, or other character. The patterns match the whole value, so nothing
# but those digits reaches the temporary configuration.
validate_options() {
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  readonly CLEANUP
  case "${PARALLELDOWNLOADS}" in
    "" | [123456789] | 1[0123456789] | 20) ;;
    *)
      fail "option parallelDownloads is \"${PARALLELDOWNLOADS}\";" \
        "use a whole number from 1 through 20, or leave it empty to inherit the image's setting"
      ;;
  esac
  readonly PARALLELDOWNLOADS
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

# Succeeds when the target $1 matches ^[A-Za-z0-9][A-Za-z0-9@._+:<>=-]*$. The character sets here and in
# is_repository_name are spelled out instead of written as ranges, which some shells read by locale collation.
is_target() {
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | \
      *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+:\<\>=-]*)
      return 1
      ;;
  esac
}

# Succeeds when the repository name $1 matches ^[A-Za-z0-9][A-Za-z0-9._+-]*$.
is_repository_name() {
  case "$1" in
    "" | [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | \
      *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-]*)
      return 1
      ;;
  esac
}

# Fails unless the entry $1 is a target or a repository-qualified target, repository/target. An entry holding "/" that
# starts with "/" or ".", holds "://", or holds a second "/" is refused as a path or URL; every other refused entry
# holding "/" as a malformed repository qualifier. Whether the repository exists is left to pacman.
check_entry() {
  case "$1" in
    /* | .*/* | *://* | */*/*)
      fail "refusing the entry '$1': paths and URLs are not accepted, because the feature installs only from the" \
        "image's repositories; name a package, optionally as repository/target"
      ;;
    */*)
      if ! is_repository_name "${1%%/*}" || ! is_target "${1#*/}"; then
        fail "refusing the entry '$1': malformed repository qualifier; use repository/target, where the repository" \
          "starts with an ASCII letter or digit and uses only ASCII letters, digits, and . _ + -, and the target is" \
          "a package, provided, or group name with an optional version constraint"
      fi
      ;;
    *)
      is_target "$1" \
        || fail "refusing the entry '$1': not a package, provided, or group name with an optional version constraint;" \
          "start with an ASCII letter or digit and use only ASCII letters, digits, and @ . _ + - : < > ="
      ;;
  esac
}

# Fails unless pacman is on PATH, naming the distribution /etc/os-release describes.
require_pacman() {
  if command -v pacman >/dev/null 2>&1; then return 0; fi
  require_pacman_distribution=""
  if [ -r /etc/os-release ]; then
    # A malformed /etc/os-release, or one that assigns a readonly name, fails the subshell. The message below must
    # still be the one that ends the run, so the distribution then stays unidentified.
    # shellcheck source=/dev/null
    if ! require_pacman_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"; then
      require_pacman_distribution=""
    fi
  fi
  fail "pacman was not found on this image (${require_pacman_distribution:-an unidentified distribution});" \
    "use an Arch Linux image, which provides pacman"
}

# Removes the temporary configuration on every exit, success or failure.
remove_temporary_configuration() {
  if [ -n "${temporary_configuration}" ]; then rm --force -- "${temporary_configuration}"; fi
}

# Writes the temporary configuration, which gives pacman the image's whole configuration with ParallelDownloads
# replaced, and fails unless pacman-conf resolves the requested value from it. pacman takes the setting from its
# configuration alone. The second [options] header puts the setting in the options section whichever section the
# included file ends in, and after the inclusion, because the last assignment wins.
write_temporary_configuration() {
  trap remove_temporary_configuration EXIT
  # A trapped signal ends the script through the exit trap; each status is 128 plus the signal's number.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  temporary_configuration="$(mktemp "${TEMPORARY_CONFIGURATION_TEMPLATE}")" \
    || fail "cannot create the temporary pacman configuration that parallelDownloads needs; make /tmp writable"
  log "writing the temporary pacman configuration ${temporary_configuration}, which includes ${IMAGE_CONFIGURATION}" \
    "and sets ParallelDownloads = ${PARALLELDOWNLOADS} (parallelDownloads=${PARALLELDOWNLOADS})"
  printf '[options]\nInclude = %s\n[options]\nParallelDownloads = %s\n' \
    "${IMAGE_CONFIGURATION}" "${PARALLELDOWNLOADS}" >"${temporary_configuration}"
  # pacman only warns about a setting it does not know and goes on without it, and pacman-conf fails when the included
  # file cannot be read. So the value pacman-conf resolves is compared before pacman runs.
  write_temporary_configuration_resolved="$(pacman-conf --config "${temporary_configuration}" ParallelDownloads)" \
    || fail "cannot apply parallelDownloads=${PARALLELDOWNLOADS}: pacman-conf did not resolve ParallelDownloads from" \
      "${IMAGE_CONFIGURATION}; check that the file exists and that this pacman provides pacman-conf and the" \
      "setting, or leave parallelDownloads empty"
  if [ "${write_temporary_configuration_resolved}" != "${PARALLELDOWNLOADS}" ]; then
    fail "cannot apply parallelDownloads=${PARALLELDOWNLOADS}: pacman-conf resolves ParallelDownloads as" \
      "\"${write_temporary_configuration_resolved}\"; leave parallelDownloads empty to use the image's setting"
  fi
}

# Installs the entries given as arguments in one transaction that also synchronizes every database and upgrades the
# system (Arch Linux supports no partial upgrade). --needed skips a listed package that is already up to date, and
# --noconfirm takes pacman's default answer to every question. --config names the temporary configuration, which
# exists only for a non-empty parallelDownloads.
install_packages() {
  log "upgrading the system and installing $* from the image's repositories"
  if [ -n "${temporary_configuration}" ]; then
    pacman --config "${temporary_configuration}" --sync --refresh --sysupgrade --needed --noconfirm -- "$@" \
      || fail "pacman --sync failed with status $?;" \
        "fix what pacman reports above (entries, repositories, mirrors, keyring, or network)"
  else
    pacman --sync --refresh --sysupgrade --needed --noconfirm -- "$@" \
      || fail "pacman --sync failed with status $?;" \
        "fix what pacman reports above (entries, repositories, mirrors, keyring, or network)"
  fi
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
  # The options and every entry are checked before anything else happens, and the accepted entries become main's
  # positional parameters, so each reaches pacman as one argument and none is evaluated as shell code. The checks run
  # in the C locale, where a bracket expression matches single bytes and so no non-ASCII letter or digit; the locale
  # the build set is restored afterwards, so pacman and the packages' install scripts run in it.
  main_locale_was_set="${LC_ALL+yes}"
  main_locale_before="${LC_ALL-}"
  LC_ALL=C
  validate_options
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
  require_pacman
  if [ -n "${PARALLELDOWNLOADS}" ]; then write_temporary_configuration; fi
  install_packages "$@"
  clean_caches
}

main "$@"
