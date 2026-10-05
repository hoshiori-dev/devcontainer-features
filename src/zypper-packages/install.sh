#!/bin/sh
# Installs the packages listed in the option `packages` with zypper from the image's enabled repositories, to the paths
# the packages define. Runs as root at image build time; the options arrive as PACKAGES, INSTALLRECOMMENDS,
# REFRESHPOLICY, and CLEANUP.
# POSIX sh, because an empty list must succeed, and a missing zypper be reported, on images that ship no bash.
set -eu

# libzypp's defaults: its configuration file, its cache directory, and the raw metadata directory below that one.
readonly ZYPP_CONF_DEFAULT="/etc/zypp/zypp.conf"
readonly ZYPP_CACHE_DIR_DEFAULT="/var/cache/zypp"
readonly ZYPP_RAW_SUBDIR_DEFAULT="raw"

PACKAGES="${PACKAGES-}"
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"

# Set by trim: its argument without the surrounding whitespace.
trim_result=""

log() {
  printf 'zypper-packages: %s\n' "$*"
}

fail() {
  printf 'zypper-packages: error: %s\n' "$*" >&2
  exit 1
}

# Sets trim_result to $1 without leading and trailing whitespace.
trim() {
  trim_result="$1"
  while :; do
    case "${trim_result}" in
      [[:space:]]*) trim_result="${trim_result#?}" ;;
      *) break ;;
    esac
  done
  while :; do
    case "${trim_result}" in
      *[[:space:]]) trim_result="${trim_result%?}" ;;
      *) break ;;
    esac
  done
}

# Accepts a package name with an optional architecture, alone or followed by one operator and an edition; $1 is the
# trimmed entry. Fails on any other entry. Runs under LC_ALL=C, where the ranges match ASCII letters and digits only.
check_entry() {
  check_entry_name="${1%%[=<>]*}"
  # What follows the name: nothing, or an operator and an edition. The operator is removed below.
  check_entry_edition="${1#"${check_entry_name}"}"
  # The empty pattern is quoted against the style guide: an empty pattern cannot be written unquoted.
  case "${check_entry_name}" in
    "" | [!A-Za-z0-9]* | *[!A-Za-z0-9._+-]*)
      fail "refusing the entry '$1': not a package name; use name, name.arch, name=edition, or name>=edition"
      ;;
  esac
  # The empty pattern and the patterns with < or > are quoted against the style guide: an empty pattern cannot be
  # written unquoted, and an unquoted < or > is a redirection.
  case "${check_entry_edition}" in
    "") ;;
    '<='* | '>='*) check_entry_edition="${check_entry_edition#??}" ;;
    =* | '<'* | '>'*) check_entry_edition="${check_entry_edition#?}" ;;
  esac
  case "${check_entry_edition}" in
    *[!A-Za-z0-9._+~^:-]*)
      fail "refusing the entry '$1': invalid version; use one operator and an edition of A-Z a-z 0-9 . _ + ~ ^ : -"
      ;;
  esac
  if [ "${check_entry_name}" != "$1" ] && [ -z "${check_entry_edition}" ]; then
    fail "refusing the entry '$1': no version follows the operator; add an edition or remove the operator"
  fi
  case "$1" in
    *.rpm) fail "refusing the entry '$1': RPM files are not accepted; list the package name instead" ;;
  esac
}

validate_options() {
  case "${INSTALLRECOMMENDS}" in
    true | false) ;;
    *) fail "option installRecommends is \"${INSTALLRECOMMENDS}\"; use true or false" ;;
  esac
  case "${REFRESHPOLICY}" in
    default | always | never) ;;
    *) fail "option refreshPolicy is \"${REFRESHPOLICY}\"; use default, always, or never" ;;
  esac
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  readonly INSTALLRECOMMENDS REFRESHPOLICY CLEANUP
}

# Fails unless zypper is on PATH. The message names the distribution, read from /etc/os-release with builtins only, so
# that it also appears on an image that offers no other command.
require_zypper() {
  if command -v zypper >/dev/null 2>&1; then return 0; fi
  require_zypper_distribution=""
  if [ -r /etc/os-release ]; then
    # A malformed /etc/os-release, or one that assigns a readonly name, fails the subshell. The message below must
    # still be the one that ends the run, so the distribution then stays unidentified.
    # shellcheck source=/dev/null
    if ! require_zypper_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"; then
      require_zypper_distribution=""
    fi
  fi
  fail "zypper was not found on this image (${require_zypper_distribution:-an unidentified distribution});" \
    "use an openSUSE image, which provides zypper"
}

# Refreshes every enabled repository in a step of its own, so that a repository that cannot be refreshed or verified
# fails the build before anything is installed.
refresh_metadata() {
  log "refreshing the repository metadata from the image's enabled repositories (refreshPolicy=${REFRESHPOLICY})"
  # Against the style guide's rule on repeated arguments, every zypper call in this file spells out --non-interactive
  # and --no-refresh instead of taking them from a function: whoever checks a call sees every flag zypper is run with.
  zypper --non-interactive refresh \
    || fail "zypper refresh failed with status $?; fix what zypper reports above (repositories, keys, or network)"
}

# Fails when an enabled repository has no cached raw metadata: zypper would otherwise download what is missing, which
# refreshPolicy=never rules out.
check_cache() {
  # libzypp takes its cache paths from the file ZYPP_CONF names. The variable stays as inherited, and the file is only
  # read: no setting is persisted or sourced.
  check_cache_conf="${ZYPP_CONF-${ZYPP_CONF_DEFAULT}}"
  check_cache_dir="${ZYPP_CACHE_DIR_DEFAULT}"
  check_cache_raw_dir=""
  if [ -r "${check_cache_conf}" ]; then
    while IFS= read -r check_cache_line || [ -n "${check_cache_line}" ]; do
      case "${check_cache_line}" in
        *=*) ;;
        *) continue ;;
      esac
      trim "${check_cache_line%%=*}"
      case "${trim_result}" in
        cachedir)
          trim "${check_cache_line#*=}"
          if [ -n "${trim_result}" ]; then check_cache_dir="${trim_result}"; fi
          ;;
        metadatadir)
          trim "${check_cache_line#*=}"
          check_cache_raw_dir="${trim_result}"
          ;;
      esac
    done <"${check_cache_conf}"
  fi
  if [ -z "${check_cache_raw_dir}" ]; then check_cache_raw_dir="${check_cache_dir}/${ZYPP_RAW_SUBDIR_DEFAULT}"; fi

  log "using the repository metadata the image already holds in ${check_cache_raw_dir} (refreshPolicy=never)"
  check_cache_repos="$(zypper --xmlout --non-interactive --no-refresh repos)" \
    || fail "zypper repos failed with status $?; fix what zypper reports above (the image's repository configuration)"
  check_cache_aliases="$(
    sed --quiet '/<repo .*enabled="1"/s/.*alias="\([^"]*\)".*/\1/p' <<EOF
${check_cache_repos}
EOF
  )"
  [ -n "${check_cache_aliases}" ] || fail "refreshPolicy=never needs an enabled repository; enable one in the image"
  while IFS= read -r check_cache_alias; do
    if [ ! -s "${check_cache_raw_dir}/${check_cache_alias}/repodata/repomd.xml" ] \
      && [ ! -s "${check_cache_raw_dir}/${check_cache_alias}/content" ]; then
      fail "refreshPolicy=never needs cached metadata for '${check_cache_alias}' in ${check_cache_raw_dir};" \
        "add it to the image, or use refreshPolicy=default"
    fi
  done <<EOF
${check_cache_aliases}
EOF
}

# With raw metadata present, `refresh --build-only` validates every repository's cache before installation and can
# rebuild a missing parsed cache without refreshing.
build_parsed_cache() {
  log "building zypper's parsed cache from that metadata, without refreshing"
  zypper --non-interactive --no-refresh refresh --build-only \
    || fail "zypper refresh --build-only failed with status $?;" \
      "fix the cached repository metadata, or use refreshPolicy=default"
}

# Installs the accepted entries, $@, each as one argument after --, from the metadata the earlier step selected.
install_packages() {
  log "installing $* from the image's enabled repositories (installRecommends=${INSTALLRECOMMENDS})"
  case "${INSTALLRECOMMENDS}" in
    true) install_packages_recommends="--recommends" ;;
    false) install_packages_recommends="--no-recommends" ;;
  esac
  zypper --non-interactive --no-refresh install "${install_packages_recommends}" -- "$@" \
    || fail "zypper install failed with status $?; fix what zypper reports above (entries, repositories, or network)"
}

clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages and the repository metadata from zypper's caches (cleanup=all)"
      zypper --non-interactive clean --all \
        || fail "zypper clean failed with status $?; fix what zypper reports above, or use cleanup=none"
      ;;
    packages)
      log "removing downloaded packages from zypper's caches (cleanup=packages)"
      zypper --non-interactive clean \
        || fail "zypper clean failed with status $?; fix what zypper reports above, or use cleanup=none"
      ;;
    none) ;;
  esac
}

main() {
  # The controls are validated before any zypper call and before the empty-list exit: an invalid control fails also
  # when no package is listed.
  validate_options

  # The accepted entries are collected in main's positional parameters: POSIX sh has no arrays, and a `set --` inside a
  # function is lost when it returns. LC_ALL is C only while the entries are split, trimmed, and checked, so that
  # whitespace and the allowlist ranges are ASCII; afterwards it is as it was, set or unset.
  main_locale_was_set="${LC_ALL+yes}"
  main_locale_before="${LC_ALL-}"
  LC_ALL=C
  set --
  main_rest="${PACKAGES},"
  while [ -n "${main_rest}" ]; do
    main_entry="${main_rest%%,*}"
    main_rest="${main_rest#*,}"
    trim "${main_entry}"
    if [ -z "${trim_result}" ]; then continue; fi
    check_entry "${trim_result}"
    set -- "$@" "${trim_result}"
  done
  if [ -n "${main_locale_was_set}" ]; then
    LC_ALL="${main_locale_before}"
  else
    unset LC_ALL
  fi
  readonly PACKAGES

  if [ "$#" -eq 0 ]; then
    log "no packages listed; nothing to do"
    return 0
  fi

  require_zypper
  if [ "${REFRESHPOLICY}" = "never" ]; then
    check_cache
    build_parsed_cache
  else
    refresh_metadata
  fi
  install_packages "$@"
  clean_caches
}

main "$@"
