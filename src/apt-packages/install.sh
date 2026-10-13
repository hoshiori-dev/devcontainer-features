#!/bin/sh
# Installs the packages listed in the option `packages` with apt-get from the image's repositories, to the paths the
# packages define. Runs as root at image build time; the options arrive as PACKAGES, INSTALLRECOMMENDS, INSTALLSUGGESTS,
# REFRESHPOLICY, CLEANUP, CONFFILEPOLICY, NETWORKTIMEOUT, DOWNLOADRETRIES, LOCKTIMEOUT, and TARGETRELEASE.
# POSIX sh, because an empty list must succeed, and a missing apt-get be reported, on images that ship no bash.
set -eu

# Package configuration questions take their default answers: an image build has no terminal to ask on.
export DEBIAN_FRONTEND=noninteractive
readonly DEBIAN_FRONTEND

PACKAGES="${PACKAGES-}"
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
INSTALLSUGGESTS="${INSTALLSUGGESTS-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
CONFFILEPOLICY="${CONFFILEPOLICY-keep}"
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"
DOWNLOADRETRIES="${DOWNLOADRETRIES-}"
LOCKTIMEOUT="${LOCKTIMEOUT-}"
TARGETRELEASE="${TARGETRELEASE-}"

# APT's package index directory, which cleanup=all empties. It is no constant: an image's APT configuration may move
# it, so resolve_lists_dir asks apt-config for it at run time.
lists_dir=""

log() {
  printf 'apt-packages: %s\n' "$*"
}

fail() {
  printf 'apt-packages: error: %s\n' "$*" >&2
  exit 1
}

# Succeeds when the package index directory holds the package list of at least one repository.
has_index() {
  for has_index_list in "${lists_dir}"/*_Packages*; do
    if [ -e "${has_index_list}" ]; then return 0; fi
  done
  return 1
}

# Runs apt-get with the arguments given. Before them come the option downloadRetries, unless it is empty, as APT's
# retry count, and the option networkTimeout, unless it is empty, as APT's HTTP and HTTPS timeout.
apt_network() {
  if [ -n "${DOWNLOADRETRIES}" ]; then
    set -- --option "Acquire::Retries=${DOWNLOADRETRIES}" "$@"
  fi
  if [ -n "${NETWORKTIMEOUT}" ]; then
    set -- --option "Acquire::http::Timeout=${NETWORKTIMEOUT}" \
      --option "Acquire::https::Timeout=${NETWORKTIMEOUT}" "$@"
  fi
  apt-get "$@"
}

validate_options() {
  case "${INSTALLRECOMMENDS}" in
    true | false) ;;
    *) fail "option installRecommends is \"${INSTALLRECOMMENDS}\"; use true or false" ;;
  esac
  readonly INSTALLRECOMMENDS
  case "${INSTALLSUGGESTS}" in
    true | false) ;;
    *) fail "option installSuggests is \"${INSTALLSUGGESTS}\"; use true or false" ;;
  esac
  readonly INSTALLSUGGESTS
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
  case "${CONFFILEPOLICY}" in
    keep | replace) ;;
    *) fail "option conffilePolicy is \"${CONFFILEPOLICY}\"; use keep or replace" ;;
  esac
  readonly CONFFILEPOLICY
  validate_options_hint="leave it empty or use whole seconds from 1 through 3600 without a leading zero"
  case "${NETWORKTIMEOUT}" in
    "") ;;
    0* | *[!0123456789]*) fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_options_hint}" ;;
    *)
      # The length test comes first: dash cannot compare a number beyond its integer range, so the second test alone
      # would print "Illegal number", count as false, and accept the value.
      if [ "${#NETWORKTIMEOUT}" -gt 4 ] || [ "${NETWORKTIMEOUT}" -gt 3600 ]; then
        fail "option networkTimeout is \"${NETWORKTIMEOUT}\"; ${validate_options_hint}"
      fi
      ;;
  esac
  readonly NETWORKTIMEOUT
  # APT would read a negative or oversized retry count as unbounded and replace any other malformed number with a
  # value of its own, so only the canonical spelling of 0 through 10 passes.
  validate_options_hint="leave it empty or use a number from 0 through 10 without a leading zero"
  case "${DOWNLOADRETRIES}" in
    "" | 0) ;;
    0* | *[!0123456789]*) fail "option downloadRetries is \"${DOWNLOADRETRIES}\"; ${validate_options_hint}" ;;
    *)
      # The length test comes first, as for networkTimeout.
      if [ "${#DOWNLOADRETRIES}" -gt 2 ] || [ "${DOWNLOADRETRIES}" -gt 10 ]; then
        fail "option downloadRetries is \"${DOWNLOADRETRIES}\"; ${validate_options_hint}"
      fi
      ;;
  esac
  readonly DOWNLOADRETRIES
  # APT would read a negative lock wait as unbounded and any other malformed number as no wait.
  validate_options_hint="leave it empty or use whole seconds from 1 through 3600 without a leading zero"
  case "${LOCKTIMEOUT}" in
    "") ;;
    0* | *[!0123456789]*) fail "option lockTimeout is \"${LOCKTIMEOUT}\"; ${validate_options_hint}" ;;
    *)
      # The length test comes first, as for networkTimeout.
      if [ "${#LOCKTIMEOUT}" -gt 4 ] || [ "${LOCKTIMEOUT}" -gt 3600 ]; then
        fail "option lockTimeout is \"${LOCKTIMEOUT}\"; ${validate_options_hint}"
      fi
      ;;
  esac
  readonly LOCKTIMEOUT
  # APT would also take a pattern, a regular expression, a key=value selector, which it does not check, and "now",
  # which names the installed packages and no source. The character sets are spelled out, because some shells read a
  # range such as a-z by locale collation.
  validate_options_hint="leave it empty or use one suite name, codename, or version of at most 64 characters:"
  validate_options_hint="${validate_options_hint} letters, digits, and . + _ ~ -, starting with a letter or digit"
  case "${TARGETRELEASE}" in
    "") ;;
    [nN][oO][wW])
      fail "option targetRelease is \"${TARGETRELEASE}\", which names the installed packages and no release;" \
        "leave it empty or name a release of the image's sources"
      ;;
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | \
      *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+_~-]*)
      fail "option targetRelease is \"${TARGETRELEASE}\"; ${validate_options_hint}"
      ;;
    *)
      if [ "${#TARGETRELEASE}" -gt 64 ]; then
        fail "option targetRelease is \"${TARGETRELEASE}\"; ${validate_options_hint}"
      fi
      ;;
  esac
  readonly TARGETRELEASE
}

# Succeeds when the entry $1 has the form that the spec requirement "Entries are validated before anything changes"
# accepts (openspec/specs/apt-packages/spec.md).
is_accepted_entry() {
  is_accepted_entry_name="${1%%[=:]*}"
  is_accepted_entry_qualifier="${1#"${is_accepted_entry_name}"}"
  # The character sets are spelled out, because some shells read a range such as a-z by locale collation.
  case "${is_accepted_entry_name}" in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789.+-]*) return 1 ;;
  esac
  case "${is_accepted_entry_qualifier}" in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+:~=-]*) return 1 ;;
  esac
  case "$1" in
    *-) return 1 ;;
  esac
}

# Fails, naming the distribution /etc/os-release reports, unless the image provides apt-get.
require_apt_get() {
  if command -v apt-get >/dev/null 2>&1; then return 0; fi
  require_apt_get_distribution=""
  if [ -r /etc/os-release ]; then
    # A malformed /etc/os-release, or one that assigns a readonly name, fails the subshell. The message below must
    # still be the one that ends the run, so the distribution then stays unidentified.
    # shellcheck source=/dev/null
    if ! require_apt_get_distribution="$(. /etc/os-release && printf '%s\n' "${PRETTY_NAME:-}")"; then
      require_apt_get_distribution=""
    fi
  fi
  fail "apt-get was not found on this image (${require_apt_get_distribution:-an unidentified distribution});" \
    "use a Debian or Ubuntu image, which provides apt-get"
}

# Sets lists_dir to the package index directory that apt-config resolves from the image's APT configuration, an
# inherited APT_CONFIG included.
resolve_lists_dir() {
  resolve_lists_dir_output="$(apt-config shell value Dir::State::lists/d)" \
    || fail "apt-config shell failed with status $?;" \
      "fix what apt-config reports above (APT configuration or APT_CONFIG)"
  # apt-config prints value='<directory>' for a shell to evaluate; it is read as data here and never sourced.
  resolve_lists_dir_value="${resolve_lists_dir_output#"value='"}"
  lists_dir="${resolve_lists_dir_value%"'"}"
  # cleanup=all removes everything inside this directory, so an empty or root value is refused.
  case "${lists_dir}" in
    "" | /)
      fail "apt-config reports Dir::State::lists as \"${lists_dir}\";" \
        "set it to a directory other than / in the image's APT configuration"
      ;;
  esac
}

# Refreshes the package index from every configured repository, or keeps the one the image holds, as the option
# refreshPolicy selects.
refresh_index() {
  if [ "${REFRESHPOLICY}" = "never" ] && ! has_index; then
    fail "refreshPolicy=never needs a package index in ${lists_dir};" \
      "add it to the image, or use refreshPolicy=default"
  fi
  if [ "${REFRESHPOLICY}" != "always" ] && has_index; then
    log "using the package index the image already holds in ${lists_dir} (refreshPolicy=${REFRESHPOLICY})"
    return 0
  fi
  log "refreshing the package index from the image's repositories (refreshPolicy=${REFRESHPOLICY})"
  # --error-on=any: a repository that cannot be refreshed fails the update instead of ending in a warning.
  apt_network update --error-on=any \
    || fail "apt-get update failed with status $?; fix what apt-get reports above (repositories, keys, or network)"
}

# Fails unless every entry given names a package of the index exactly and, with =version, one of its available
# versions exactly.
check_names() {
  # apt-get would read a trailing + on an unknown name or version as an install marker, so each name (virtual names
  # included) and each version is compared as a whole; real names such as g++ stay valid. The lookups read the index
  # that refresh_index selected and never refresh it. Each lookup's output is saved before it is searched, so a
  # failing apt-cache is reported as such and not as a missing name or version.
  for check_names_entry in "$@"; do
    check_names_name="${check_names_entry%%[=:]*}"
    check_names_known="$(apt-cache pkgnames --all-names "${check_names_name}")" \
      || fail "apt-cache pkgnames failed with status $? for the entry '${check_names_entry}';" \
        "fix what apt-cache reports above (the package index)"
    grep --fixed-strings --line-regexp --quiet -- "${check_names_name}" <<EOF \
      || fail "the entry '${check_names_entry}' names no package in the package index;" \
        "check the spelling, or use refreshPolicy=always"
${check_names_known}
EOF
    case "${check_names_entry}" in
      *=*)
        check_names_record="$(apt-cache show -- "${check_names_entry}")" \
          || fail "apt-cache show failed with status $? for the entry '${check_names_entry}';" \
            "check its architecture and version with apt-cache policy ${check_names_name}"
        awk -v version="${check_names_entry#*=}" \
          '$1 == "Version:" && $2 == version { found = 1 } END { exit !found }' <<EOF \
          || fail "the entry '${check_names_entry}' names no available version;" \
            "pick one that apt-cache policy ${check_names_name} lists, or use refreshPolicy=always"
${check_names_record}
EOF
        ;;
    esac
  done
}

# Fails unless the option targetRelease, when it is set, would make APT prefer at least one release of the package
# index. APT's own refusal is narrower: it accepts a value that equals any release's suite name, codename, or version,
# but prefers a release by one kind of field only, chosen by the value's first character. A value that only a field of
# the other kind carries would pass APT and prefer nothing, without an error.
check_target_release() {
  if [ -z "${TARGETRELEASE}" ]; then return 0; fi
  case "${TARGETRELEASE}" in
    [0123456789]*)
      check_target_release_kind="version"
      # A placeholder of apt-get's --format, which the shell must not expand.
      # shellcheck disable=SC2016
      set -- '$(VERSION)'
      ;;
    *)
      check_target_release_kind="suite name or codename"
      # Placeholders of apt-get's --format, which the shell must not expand.
      # shellcheck disable=SC2016
      set -- '$(SUITE)' '$(CODENAME)'
      ;;
  esac
  # APT compares without regard to the case of ASCII letters. The letters are spelled out, as in validate_options.
  check_target_release_wanted="$(
    tr ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz <<EOF
${TARGETRELEASE}
EOF
  )"
  # The index-target listing prints one field of each configured source as a line of its own, and the placeholder
  # itself where a release lacks the field, which equals no accepted value. apt-cache policy is no source for the
  # fields: it joins them with commas, so a field that holds a comma reads there as a further field.
  for check_target_release_field in "$@"; do
    check_target_release_listed="$(apt-get indextargets --format "${check_target_release_field}")" \
      || fail "apt-get indextargets failed with status $?;" \
        "fix what apt-get reports above (APT configuration or the package index)"
    check_target_release_listed="$(
      tr ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz <<EOF
${check_target_release_listed}
EOF
    )"
    if grep --fixed-strings --line-regexp --quiet -- "${check_target_release_wanted}" <<EOF; then
${check_target_release_listed}
EOF
      return 0
    fi
  done
  fail "option targetRelease is \"${TARGETRELEASE}\", which is the ${check_target_release_kind} of no release in the" \
    "package index, so APT would prefer no release; use the ${check_target_release_kind} of a configured source" \
    "(a value that starts with a digit is compared with versions, any other with suite names and codenames)"
}

# Installs the entries given, each as one argument after --.
install_packages() {
  install_packages_controls="installRecommends=${INSTALLRECOMMENDS}, installSuggests=${INSTALLSUGGESTS}"
  install_packages_controls="${install_packages_controls}, conffilePolicy=${CONFFILEPOLICY}"
  if [ -n "${TARGETRELEASE}" ]; then
    install_packages_controls="${install_packages_controls}, targetRelease=${TARGETRELEASE}"
  fi
  if [ -n "${LOCKTIMEOUT}" ]; then
    install_packages_controls="${install_packages_controls}, lockTimeout=${LOCKTIMEOUT}"
  fi
  log "installing $* from the image's repositories (${install_packages_controls})"
  # The arguments that depend on an option go before the entries; the one added last comes first.
  set -- -- "$@"
  # dpkg decides without asking about a configuration file that the image changed. keep prefers dpkg's default
  # action, which keeps the file. replace refuses that default action first: where the image's own configuration
  # enables it, --force-confnew alone would keep the file.
  case "${CONFFILEPOLICY}" in
    keep) set -- --option Dpkg::Options::=--force-confdef --option Dpkg::Options::=--force-confold "$@" ;;
    replace) set -- --option Dpkg::Options::=--refuse-confdef --option Dpkg::Options::=--force-confnew "$@" ;;
  esac
  # Only the install call waits: APT waits for dpkg's locks and for no other.
  if [ -n "${LOCKTIMEOUT}" ]; then
    set -- --option "DPkg::Lock::Timeout=${LOCKTIMEOUT}" "$@"
  fi
  # Only the install call prefers a release: the refresh would accept and ignore a release that does not exist.
  # check_target_release has made sure that the value prefers one.
  if [ -n "${TARGETRELEASE}" ]; then
    set -- --target-release "${TARGETRELEASE}" "$@"
  fi
  # apt-get removes no package and matches no entry as a pattern.
  apt_network install --yes --no-remove \
    --option "APT::Install-Recommends=${INSTALLRECOMMENDS}" \
    --option "APT::Install-Suggests=${INSTALLSUGGESTS}" \
    --option APT::Cmd::Pattern-Only=true \
    "$@" \
    || fail "apt-get install failed with status $?; fix what apt-get reports above (entries, repositories, or network)"
}

clean_caches() {
  case "${CLEANUP}" in
    all)
      log "removing downloaded packages from apt-get's cache and the package index from ${lists_dir} (cleanup=all)"
      apt-get clean || fail "apt-get clean failed with status $?; fix what apt-get reports above, or use cleanup=none"
      rm --recursive --force "${lists_dir:?}"/*
      ;;
    packages)
      log "removing downloaded packages from apt-get's cache (cleanup=packages)"
      apt-get clean || fail "apt-get clean failed with status $?; fix what apt-get reports above, or use cleanup=none"
      ;;
    none) ;;
  esac
}

main() {
  validate_options

  # The accepted entries become main's positional parameters, so each one reaches apt-get as one argument and none is
  # ever evaluated as shell code. The loop stays in main: `set --` in a function changes only that function's list.
  set --
  main_rest="${PACKAGES},"
  while [ -n "${main_rest}" ]; do
    main_entry="${main_rest%%,*}"
    main_rest="${main_rest#*,}"
    # Remove the whitespace before the entry, then the whitespace after it.
    main_entry="${main_entry#"${main_entry%%[![:space:]]*}"}"
    main_entry="${main_entry%"${main_entry##*[![:space:]]}"}"
    if [ -z "${main_entry}" ]; then continue; fi
    if ! is_accepted_entry "${main_entry}"; then
      fail "refusing the entry '${main_entry}': not a package name with an optional :architecture or =version;" \
        "start with a lower-case letter or digit, use only letters, digits, and . + - : ~ =, and do not end in -"
    fi
    set -- "$@" "${main_entry}"
  done
  readonly PACKAGES

  if [ "$#" -eq 0 ]; then
    log "no packages listed; nothing to do"
    return 0
  fi

  # The spec fixes the place of three checks that the guide would put before this point: apt-get is required only for
  # a list that names a package, and exact names and the release that targetRelease names can be checked only against
  # the index that refresh_index selects. A failing entry ends the run before the release is looked at.
  require_apt_get
  resolve_lists_dir
  refresh_index
  check_names "$@"
  check_target_release
  install_packages "$@"
  clean_caches
}

main "$@"
