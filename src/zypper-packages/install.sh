#!/bin/sh
# Installs the packages listed in the option `packages` with zypper from the image's enabled repositories, or from those
# of them that the option `repositories` selects, to the paths the packages define. Runs as root at image build time;
# the options arrive as PACKAGES, INSTALLRECOMMENDS, EXACTNAMES, REFRESHPOLICY, CLEANUP, REPOSITORIES, LOCKTIMEOUT,
# CONNECTTIMEOUT, TRANSFERTIMEOUT, and DOWNLOADRETRIES.
# POSIX sh, because an empty list must succeed, and a missing zypper be reported, on images that ship no bash.
set -eu

# libzypp's defaults: its configuration file, its cache directory, and the raw metadata directory below that one.
readonly ZYPP_CONF_DEFAULT="/etc/zypp/zypp.conf"
readonly ZYPP_CACHE_DIR_DEFAULT="/var/cache/zypp"
readonly ZYPP_RAW_SUBDIR_DEFAULT="raw"
# Where the timeout and retry options travel: one temporary file, written only when one of them is set and removed when
# the feature exits, in a directory whose files libzypp reads in addition to the image's configuration. The feature
# creates the two directories when they are missing and removes those it created. The file's name sorts after ordinary
# names, so that libzypp reads it last, and mktemp replaces the X's, so that it is never an existing file.
readonly ZYPP_OVERRIDE_PARENT="/run/zypp"
readonly ZYPP_OVERRIDE_DIR="/run/zypp/zypp.conf.d"
readonly ZYPP_OVERRIDE_TEMPLATE="zzzz-zypper-packages-feature.XXXXXXXX.conf"
# The RPM capability of every libzypp that reads such additional configuration files (zypp.conf(5)).
readonly ZYPP_DROPIN_CAPABILITY="libzypp(econf)"
readonly NEWLINE='
'

PACKAGES="${PACKAGES-}"
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
EXACTNAMES="${EXACTNAMES-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
REPOSITORIES="${REPOSITORIES-}"
LOCKTIMEOUT="${LOCKTIMEOUT-}"
CONNECTTIMEOUT="${CONNECTTIMEOUT-}"
TRANSFERTIMEOUT="${TRANSFERTIMEOUT-}"
DOWNLOADRETRIES="${DOWNLOADRETRIES-}"

# Set by trim: its argument without the surrounding whitespace.
trim_result=""
# Set by attribute: the value of the attribute it was asked for.
attribute_result=""
# Set by parse_repositories: the aliases that the option repositories names, one per line, and the same joined by
# spaces for messages.
selection=""
selection_text=""
# Set by validate_options: the names of the timeout and retry options that are not empty, joined by ", ".
override_options=""
# Set by list_repositories: zypper's listing of the image's repositories.
repositories_xml=""
# Set by write_overrides and read by remove_overrides: the temporary file, and "yes" for each directory the feature created.
override_file=""
override_dir_created=""
override_parent_created=""

log() {
  printf 'zypper-packages: %s\n' "$*"
}

fail() {
  printf 'zypper-packages: error: %s\n' "$*" >&2
  exit 1
}

# Removes the temporary configuration file and the directories the feature created for it, on every exit, success or
# failure. A directory that holds something else by then stays. Not named after the option cleanup, which is about
# zypper's caches.
remove_overrides() {
  if [ -n "${override_file}" ]; then
    rm --force "${override_file}" || log "could not remove ${override_file}"
  fi
  if [ -n "${override_dir_created}" ]; then
    rmdir "${ZYPP_OVERRIDE_DIR}" || log "left ${ZYPP_OVERRIDE_DIR} in place"
  fi
  if [ -n "${override_parent_created}" ]; then
    rmdir "${ZYPP_OVERRIDE_PARENT}" || log "left ${ZYPP_OVERRIDE_PARENT} in place"
  fi
}

# Runs zypper with the arguments given; every caller spells out its zypper flags. With a non-empty lockTimeout this
# call, and nothing else, gets ZYPP_LOCK_TIMEOUT, libzypp's documented override of its lock wait; with an empty one the
# environment is passed on as it is.
run_zypper() {
  if [ -n "${LOCKTIMEOUT}" ]; then
    ZYPP_LOCK_TIMEOUT="${LOCKTIMEOUT}" zypper "$@"
  else
    zypper "$@"
  fi
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

# Sets attribute_result to the value of the attribute $2 in the XML start tag $1, or to nothing when the tag has none.
# A value holds no double quote of its own: XML writes one as an entity.
attribute() {
  case "$1" in
    *" $2=\""*)
      attribute_result="${1#*" $2=\""}"
      attribute_result="${attribute_result%%\"*}"
      ;;
    *) attribute_result="" ;;
  esac
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

# Fails unless $2, the value of the option $1, is empty or a decimal integer from $3 through $4, written in digits only
# and without a leading zero. Runs under LC_ALL=C, where the range matches ASCII digits only. The length is compared
# before the number, so that no value is too long for the shell's arithmetic. Three of these values are written into a
# libzypp configuration file, and this check is what keeps everything but digits out of it.
check_number() {
  # The empty pattern is quoted against the style guide: an empty pattern cannot be written unquoted.
  case "$2" in
    "") return 0 ;;
    *[!0-9]* | 0?*) check_number_digits="false" ;;
    *) check_number_digits="true" ;;
  esac
  if [ "${check_number_digits}" = "true" ] && [ "${#2}" -le "${#4}" ] && [ "$2" -ge "$3" ] && [ "$2" -le "$4" ]; then
    return 0
  fi
  fail "option $1 is \"$2\"; use a whole number from $3 through $4, in digits only and without a leading zero," \
    "or leave it empty to inherit the image's setting"
}

# Sets selection to the aliases that the option repositories names, one per line and each once, and selection_text to
# the same joined by spaces. Fails on an item that is not written like an alias, which refuses a repository number, a
# URI, a path, a glob, and an option. Runs under LC_ALL=C, where whitespace and the allowlist ranges are ASCII.
parse_repositories() {
  parse_repositories_rest="${REPOSITORIES},"
  while [ -n "${parse_repositories_rest}" ]; do
    parse_repositories_item="${parse_repositories_rest%%,*}"
    parse_repositories_rest="${parse_repositories_rest#*,}"
    trim "${parse_repositories_item}"
    if [ -z "${trim_result}" ]; then continue; fi
    case "${trim_result}" in
      [!A-Za-z0-9]* | *[!A-Za-z0-9._:+-]*)
        fail "option repositories holds '${trim_result}', which is not a repository alias; write each alias as" \
          "\`zypper lr\` shows it: it starts with a letter or digit and consists of A-Z a-z 0-9 . _ : + -"
        ;;
    esac
    case "${trim_result}" in
      *[!0-9]*) ;;
      *)
        fail "option repositories holds '${trim_result}', a repository number, which is not accepted;" \
          "write the repository's alias as \`zypper lr\` shows it"
        ;;
    esac
    case "${NEWLINE}${selection}${NEWLINE}" in
      *"${NEWLINE}${trim_result}${NEWLINE}"*) continue ;;
    esac
    selection="${selection:+${selection}${NEWLINE}}${trim_result}"
    selection_text="${selection_text:+${selection_text} }${trim_result}"
  done
}

validate_options() {
  case "${INSTALLRECOMMENDS}" in
    true | false) ;;
    *) fail "option installRecommends is \"${INSTALLRECOMMENDS}\"; use true or false" ;;
  esac
  case "${EXACTNAMES}" in
    true | false) ;;
    *) fail "option exactNames is \"${EXACTNAMES}\"; use true or false" ;;
  esac
  case "${REFRESHPOLICY}" in
    default | always | never) ;;
    *) fail "option refreshPolicy is \"${REFRESHPOLICY}\"; use default, always, or never" ;;
  esac
  case "${CLEANUP}" in
    all | packages | none) ;;
    *) fail "option cleanup is \"${CLEANUP}\"; use all, packages, or none" ;;
  esac
  parse_repositories
  check_number lockTimeout "${LOCKTIMEOUT}" 1 3600
  check_number connectTimeout "${CONNECTTIMEOUT}" 1 3600
  check_number transferTimeout "${TRANSFERTIMEOUT}" 1 3600
  check_number downloadRetries "${DOWNLOADRETRIES}" 0 10
  if [ -n "${CONNECTTIMEOUT}" ]; then override_options="connectTimeout"; fi
  if [ -n "${TRANSFERTIMEOUT}" ]; then override_options="${override_options:+${override_options}, }transferTimeout"; fi
  if [ -n "${DOWNLOADRETRIES}" ]; then override_options="${override_options:+${override_options}, }downloadRetries"; fi
  readonly INSTALLRECOMMENDS EXACTNAMES REFRESHPOLICY CLEANUP REPOSITORIES
  readonly LOCKTIMEOUT CONNECTTIMEOUT TRANSFERTIMEOUT DOWNLOADRETRIES
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

# Fails when a timeout or retry option is set and libzypp would not read the temporary file that carries it: with
# ZYPP_CONF set, to an empty value too, libzypp reads solely the file that variable names, and a libzypp without the
# capability reads no additional files at all. An option that silently did nothing would be a false control.
require_override_support() {
  if [ -n "${ZYPP_CONF+set}" ]; then
    fail "${override_options} cannot take effect while ZYPP_CONF is set in the build environment, because libzypp" \
      "then reads only the file ZYPP_CONF names; unset ZYPP_CONF, or leave ${override_options} empty and set the" \
      "values in that file"
  fi
  rpm --query --whatprovides "${ZYPP_DROPIN_CAPABILITY}" >/dev/null 2>&1 \
    || fail "${override_options} cannot take effect on this image: its libzypp does not provide" \
      "${ZYPP_DROPIN_CAPABILITY}, so it reads no additional configuration files; leave ${override_options} empty," \
      "or use an image with a libzypp that provides it"
}

# Sets repositories_xml to zypper's listing of the image's repositories, one <repo> start tag on a line for each.
list_repositories() {
  if [ -n "${repositories_xml}" ]; then return 0; fi
  repositories_xml="$(run_zypper --xmlout --non-interactive --no-refresh repos)" \
    || fail "zypper repos failed with status $?; fix what zypper reports above (the image's repository configuration)"
}

# Fails unless every selected alias is, in the same spelling, the alias of a repository the image enables, and the name
# of no other repository the image defines: zypper reads `--repo <text>` as an alias or a name, so a repository of that
# name could be taken for the selected one. Nothing is enabled, added, or edited to make a selection valid.
check_selection() {
  list_repositories
  while IFS= read -r check_selection_alias; do
    check_selection_state="unknown"
    check_selection_namesake=""
    while IFS= read -r check_selection_tag; do
      case "${check_selection_tag}" in
        "<repo "*) ;;
        *) continue ;;
      esac
      attribute "${check_selection_tag}" alias
      if [ "${attribute_result}" = "${check_selection_alias}" ]; then
        attribute "${check_selection_tag}" enabled
        if [ "${attribute_result}" = "1" ]; then
          check_selection_state="enabled"
        else
          check_selection_state="disabled"
        fi
        continue
      fi
      check_selection_other="${attribute_result}"
      attribute "${check_selection_tag}" name
      if [ "${attribute_result}" = "${check_selection_alias}" ]; then
        check_selection_namesake="${check_selection_other}"
      fi
    done <<EOF
${repositories_xml}
EOF
    case "${check_selection_state}" in
      unknown)
        fail "option repositories names '${check_selection_alias}', which is not the alias of a repository this" \
          "image enables; copy the alias from \`zypper lr\`, in the same letter case and with its prefix (a" \
          "repository's name, number, or URI is not accepted)"
        ;;
      disabled)
        fail "option repositories names '${check_selection_alias}', a repository this image defines but disables;" \
          "the feature enables no repository, so enable it in the image or remove it from repositories"
        ;;
    esac
    if [ -n "${check_selection_namesake}" ]; then
      fail "option repositories names '${check_selection_alias}', which is also the name of the repository" \
        "'${check_selection_namesake}', so zypper could take that one for it; rename one of the two in the image," \
        "or remove '${check_selection_alias}' from repositories"
    fi
  done <<EOF
${selection}
EOF
}

# Writes the timeout and retry options that are set into the temporary configuration file, as a [main] section that
# holds their keys and nothing else. The values are digits that check_number accepted; downloadRetries counts the
# retries after the first attempt, and libzypp's key the attempts. A directory the feature creates for the file gets
# mode 0755 whatever umask the build environment hands down, so that one it cannot remove again is not left writable
# by others.
write_overrides() {
  log "writing ${override_options} to a temporary libzypp configuration file in ${ZYPP_OVERRIDE_DIR}," \
    "removed when the feature exits"
  if [ ! -d "${ZYPP_OVERRIDE_PARENT}" ]; then
    mkdir --mode 0755 "${ZYPP_OVERRIDE_PARENT}" \
      || fail "cannot create ${ZYPP_OVERRIDE_PARENT}; leave ${override_options} empty, or fix the image's /run"
    override_parent_created="yes"
  fi
  if [ ! -d "${ZYPP_OVERRIDE_DIR}" ]; then
    mkdir --mode 0755 "${ZYPP_OVERRIDE_DIR}" \
      || fail "cannot create ${ZYPP_OVERRIDE_DIR}; leave ${override_options} empty, or fix the image's /run"
    override_dir_created="yes"
  fi
  override_file="$(mktemp "${ZYPP_OVERRIDE_DIR}/${ZYPP_OVERRIDE_TEMPLATE}")" \
    || fail "cannot create a file in ${ZYPP_OVERRIDE_DIR}; leave ${override_options} empty, or fix the image's /run"
  {
    printf '[main]\n'
    if [ -n "${CONNECTTIMEOUT}" ]; then printf 'download.connect_timeout = %s\n' "${CONNECTTIMEOUT}"; fi
    if [ -n "${TRANSFERTIMEOUT}" ]; then printf 'download.transfer_timeout = %s\n' "${TRANSFERTIMEOUT}"; fi
    if [ -n "${DOWNLOADRETRIES}" ]; then printf 'download.max_silent_tries = %s\n' "$((DOWNLOADRETRIES + 1))"; fi
  } >"${override_file}"
}

# Refreshes every repository in use, the enabled ones or the selected ones among them, in a step of its own, so that
# a repository that cannot be refreshed or verified fails the build before anything is installed.
refresh_metadata() {
  if [ -n "${selection}" ]; then
    log "refreshing the repository metadata from the selected repositories ${selection_text}" \
      "(refreshPolicy=${REFRESHPOLICY})"
    # The selection becomes this function's arguments, one `--repo <alias>` pair for each alias: POSIX sh has no
    # arrays, and an alias reaches zypper only as one quoted argument.
    while IFS= read -r refresh_metadata_alias; do
      set -- "$@" --repo "${refresh_metadata_alias}"
    done <<EOF
${selection}
EOF
  else
    log "refreshing the repository metadata from the image's enabled repositories (refreshPolicy=${REFRESHPOLICY})"
  fi
  # Against the style guide's rule on repeated arguments, every zypper call in this file spells out --non-interactive
  # and --no-refresh instead of taking them from a function: whoever checks a call sees every flag zypper is run with.
  run_zypper --non-interactive refresh "$@" \
    || fail "zypper refresh failed with status $?; fix what zypper reports above (repositories, keys, or network)"
}

# Fails when a repository in use has no cached raw metadata: zypper would otherwise download what is missing, which
# refreshPolicy=never rules out. A repository outside a selection needs none.
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
  if [ -n "${selection}" ]; then
    check_cache_aliases="${selection}"
  else
    list_repositories
    check_cache_aliases="$(
      sed --quiet '/<repo .*enabled="1"/s/.*alias="\([^"]*\)".*/\1/p' <<EOF
${repositories_xml}
EOF
    )"
  fi
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

# With raw metadata present, `refresh --build-only` validates the cache of every repository in use before installation
# and can rebuild a missing parsed cache without refreshing.
build_parsed_cache() {
  log "building zypper's parsed cache from that metadata, without refreshing"
  if [ -n "${selection}" ]; then
    # As in refresh_metadata: one `--repo <alias>` pair for each selected alias.
    while IFS= read -r build_parsed_cache_alias; do
      set -- "$@" --repo "${build_parsed_cache_alias}"
    done <<EOF
${selection}
EOF
  fi
  run_zypper --non-interactive --no-refresh refresh --build-only "$@" \
    || fail "zypper refresh --build-only failed with status $?;" \
      "fix the cached repository metadata, or use refreshPolicy=default"
}

# Installs the accepted entries, $@, each as one argument after --, from the metadata the earlier step selected.
install_packages() {
  if [ -n "${selection}" ]; then
    log "installing $* from the selected repositories ${selection_text}" \
      "(installRecommends=${INSTALLRECOMMENDS}, exactNames=${EXACTNAMES})"
  else
    log "installing $* from the image's enabled repositories" \
      "(installRecommends=${INSTALLRECOMMENDS}, exactNames=${EXACTNAMES})"
  fi
  # The arguments of `zypper install` are assembled in this function's arguments, since POSIX sh has no arrays: the
  # options are appended behind the entries, then --, and the entries are then moved behind that, one at a time. The
  # result is `--[no-]recommends [--name] [--repo <alias>]... -- <entry>...`.
  install_packages_entries="$#"
  case "${INSTALLRECOMMENDS}" in
    true) set -- "$@" --recommends ;;
    false) set -- "$@" --no-recommends ;;
  esac
  if [ "${EXACTNAMES}" = "true" ]; then set -- "$@" --name; fi
  if [ -n "${selection}" ]; then
    while IFS= read -r install_packages_alias; do
      set -- "$@" --repo "${install_packages_alias}"
    done <<EOF
${selection}
EOF
  fi
  set -- "$@" --
  while [ "${install_packages_entries}" -gt 0 ]; do
    set -- "$@" "$1"
    shift
    install_packages_entries="$((install_packages_entries - 1))"
  done
  run_zypper --non-interactive --no-refresh install "$@" \
    || fail "zypper install failed with status $?; fix what zypper reports above (entries, repositories, or network)"
}

clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages and the repository metadata from zypper's caches (cleanup=all)"
      run_zypper --non-interactive clean --all \
        || fail "zypper clean failed with status $?; fix what zypper reports above, or use cleanup=none"
      ;;
    packages)
      log "removing downloaded packages from zypper's caches (cleanup=packages)"
      run_zypper --non-interactive clean \
        || fail "zypper clean failed with status $?; fix what zypper reports above, or use cleanup=none"
      ;;
    none) ;;
  esac
}

main() {
  # LC_ALL is C only while the options and the entries are split, trimmed, and checked, so that whitespace and the
  # allowlist ranges are ASCII; afterwards it is as it was, set or unset.
  main_locale_was_set="${LC_ALL+yes}"
  main_locale_before="${LC_ALL-}"
  LC_ALL=C

  # The controls are validated before any zypper call and before the empty-list exit: an invalid control fails also
  # when no package is listed.
  validate_options

  # The accepted entries are collected in main's positional parameters: POSIX sh has no arrays, and a `set --` inside a
  # function is lost when it returns.
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
  # What a selection or an override needs from the image is checked here, before the first refresh, and only when the
  # option is set: with the options at their defaults none of these steps runs. The temporary file is written before
  # the selection is checked, because that check is the first zypper call and the file is to govern every one of them;
  # a check that fails removes the file through the trap.
  if [ -n "${override_options}" ]; then
    require_override_support
    trap remove_overrides EXIT
    write_overrides
  fi
  if [ -n "${selection}" ]; then check_selection; fi
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
