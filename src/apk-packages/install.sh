#!/bin/sh
# Installs the packages listed in the option `packages` with apk from the image's repositories, to the paths the
# packages define. Runs as root at image build time; the options arrive as PACKAGES, REFRESHPOLICY, CLEANUP,
# NETWORKTIMEOUT, and UPGRADEPACKAGES.
# POSIX sh, because Alpine images ship no bash.
set -eu

# The feature's own package cache: the one directory it creates outside a temporary directory, kept in the image
# unless cleanup=all.
readonly FEATURE_CACHE_DIR="/var/cache/apk-packages"
# The image's own caches: apk's default one, and the one an image configures through /etc/apk/cache. The feature only
# reads them, and only with refreshPolicy=never.
readonly IMAGE_CACHE_DIR="/var/cache/apk"
readonly IMAGE_CACHE_LINK="/etc/apk/cache"
# Minutes given to `apk add --cache-max-age`: the largest number whose seconds fit a signed 32-bit integer. apk add
# then treats no index as stale, so it checks no remote index after the refresh step, yet still downloads packages.
readonly CACHE_MAX_AGE_MINUTES=35791394

# No colon in the defaults: an explicitly empty value stays empty and reaches validation.
PACKAGES="${PACKAGES-}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"
UPGRADEPACKAGES="${UPGRADEPACKAGES-false}"

cache_dir=""
work_dir=""
trimmed=""
locale_was_set=""
locale_before=""

log() {
  printf 'apk-packages: %s\n' "$*"
}

fail() {
  printf 'apk-packages: error: %s\n' "$*" >&2
  exit 1
}

# Sets the global trimmed to $1 without leading and trailing whitespace.
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

# Fails with the refusal of the entry $1.
refuse() {
  fail "refusing the entry '$1': not a package name with an optional version constraint or @tag;" \
    "start with an ASCII letter or digit and use only ASCII letters, digits, and . _ + - : ~ = @ < >"
}

# Accepts $1 only when it matches ^[A-Za-z0-9][A-Za-z0-9._+:~=@<>-]*$. The character sets are spelled out instead of
# written as ranges, so the match does not depend on how a shell reads a range.
check_entry() {
  case "$1" in
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*) refuse "$1" ;;
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+:~=@\<\>-]*) refuse "$1" ;;
  esac
}

# Runs apk with the subcommand $1, then --no-interactive and --cache-dir, then the remaining arguments; --timeout
# comes before the subcommand when networkTimeout is set.
run_apk() {
  run_apk_subcommand="$1"
  shift
  if [ -n "${NETWORKTIMEOUT}" ]; then
    apk --timeout "${NETWORKTIMEOUT}" "${run_apk_subcommand}" --no-interactive --cache-dir "${cache_dir}" "$@"
  else
    apk "${run_apk_subcommand}" --no-interactive --cache-dir "${cache_dir}" "$@"
  fi
}

# Removes, on every exit, the directories the feature created for this run alone: the temporary package cache of
# cleanup=all and the work directory.
remove_temporary_dirs() {
  cd /
  if [ "${CLEANUP}" = all ] && [ -n "${cache_dir}" ]; then rm -rf -- "${cache_dir}"; fi
  if [ -n "${work_dir}" ]; then rm -rf -- "${work_dir}"; fi
}

validate_controls() {
  case "${REFRESHPOLICY}" in
    default | always | never) ;;
    *) fail "option refreshPolicy is \"${REFRESHPOLICY}\"; use default, always, or never" ;;
  esac
  readonly REFRESHPOLICY
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  readonly CLEANUP
  validate_controls_hint="leave it empty or use whole seconds from 1 through 3600 without a leading zero"
  case "${NETWORKTIMEOUT}" in
    "") ;;
    0* | *[!0123456789]*) fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_controls_hint}" ;;
    *)
      if [ "${#NETWORKTIMEOUT}" -gt 4 ] || [ "${NETWORKTIMEOUT}" -gt 3600 ]; then
        fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_controls_hint}"
      fi
      ;;
  esac
  readonly NETWORKTIMEOUT
  case "${UPGRADEPACKAGES}" in
    true | false) ;;
    *) fail "option upgradePackages is \"${UPGRADEPACKAGES}\"; use true or false" ;;
  esac
  readonly UPGRADEPACKAGES
}

# Fails unless apk is available, naming the image's distribution when /etc/os-release gives its PRETTY_NAME.
require_apk() {
  if command -v apk >/dev/null 2>&1; then return 0; fi
  require_apk_distribution=""
  if [ -r /etc/os-release ]; then
    # shellcheck source=/dev/null
    if ! require_apk_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"; then
      require_apk_distribution=""
    fi
  fi
  fail "apk was not found on this image (${require_apk_distribution:-an unidentified distribution});" \
    "use an Alpine Linux image, which provides apk"
}

# Chooses the package cache and makes a fresh work directory the current directory of the script itself, so that
# apk add cannot read an entry as a local package file.
prepare_directories() {
  if [ "${CLEANUP}" = all ]; then
    cache_dir="$(mktemp --directory "${TMPDIR:-/tmp}/apk-packages.XXXXXX")"
    log "using the temporary package cache ${cache_dir}, removed on exit (cleanup=all)"
  else
    cache_dir="${FEATURE_CACHE_DIR}"
    log "using the package cache ${FEATURE_CACHE_DIR}, kept in the image (cleanup=${CLEANUP})"
    mkdir --parents "${cache_dir}"
  fi
  work_dir="$(mktemp --directory "${TMPDIR:-/tmp}/apk-packages.XXXXXX")"
  cd "${work_dir}"
}

# Gives apk add an index of every repository: refreshed from the repositories, or with refreshPolicy=never taken
# from the caches the image already holds.
refresh_index() {
  if [ "${REFRESHPOLICY}" = never ]; then
    log "using the package index the image already holds, copied from ${IMAGE_CACHE_DIR}, ${IMAGE_CACHE_LINK}," \
      "and ${FEATURE_CACHE_DIR} to ${cache_dir} (refreshPolicy=never)"
    for refresh_index_source in "${IMAGE_CACHE_DIR}" "${IMAGE_CACHE_LINK}" "${FEATURE_CACHE_DIR}"; do
      if [ "${refresh_index_source}" = "${cache_dir}" ]; then continue; fi
      for refresh_index_file in "${refresh_index_source}"/APKINDEX.*.tar.gz "${refresh_index_source}"/*.adb; do
        if [ -f "${refresh_index_file}" ] && [ ! -e "${cache_dir}/${refresh_index_file##*/}" ]; then
          cp -p "${refresh_index_file}" "${cache_dir}/"
        fi
      done
    done
    # apk verifies offline that every repository has a usable index, so a missing one fails here and is never
    # requested from a repository.
    run_apk update --no-network \
      || fail "apk update --no-network failed with status $?;" \
        "fix the cached package index, or use refreshPolicy=default"
  else
    log "refreshing the package index from the image's repositories (refreshPolicy=${REFRESHPOLICY})"
    run_apk update \
      || fail "apk update failed with status $?; fix what apk reports above (repositories, keys, or network)"
  fi
}

# Installs the entries given as arguments; each reaches apk as one argument after the end-of-options marker.
install_packages() {
  log "installing $* from the image's repositories (upgradePackages=${UPGRADEPACKAGES})"
  set -- -- "$@"
  if [ "${UPGRADEPACKAGES}" = true ]; then set -- --upgrade "$@"; fi
  run_apk add --cache-max-age "${CACHE_MAX_AGE_MINUTES}" "$@" \
    || fail "apk add failed with status $?; fix what apk reports above (entries, repositories, or network)"
}

# Removes what cleanup selects from the feature's own caches. The temporary cache of cleanup=all goes on exit
# (remove_temporary_dirs); the image's own caches are never cleaned.
clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages and the package index from ${cache_dir} and ${FEATURE_CACHE_DIR} (cleanup=all)"
      rm -rf "${FEATURE_CACHE_DIR}"
      ;;
    packages)
      log "removing downloaded packages from ${FEATURE_CACHE_DIR} (cleanup=packages)"
      rm -f "${FEATURE_CACHE_DIR}"/*.apk
      ;;
    none) ;;
  esac
}

main() {
  # Controls and entries are matched as bytes, so no pattern can admit a non-ASCII letter. The caller's LC_ALL is
  # back in place before any apk call.
  locale_was_set="${LC_ALL+yes}"
  locale_before="${LC_ALL-}"
  LC_ALL=C
  export LC_ALL
  validate_controls
  # The accepted entries are the positional parameters of main: sh has no arrays, and a function cannot change its
  # caller's parameters. `set --` first drops any argument given to install.sh, so only validated entries are left,
  # and each reaches apk as one argument that is never evaluated as shell code.
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
  readonly PACKAGES
  if [ -n "${locale_was_set}" ]; then
    LC_ALL="${locale_before}"
  else
    unset LC_ALL
  fi
  if [ "$#" -eq 0 ]; then
    log "no packages listed; nothing to do"
    exit 0
  fi
  require_apk
  # A signal ends the script through exit, so the EXIT trap removes the temporary directories then as well.
  trap remove_temporary_dirs EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  prepare_directories
  refresh_index
  install_packages "$@"
  clean_caches
}

main "$@"
