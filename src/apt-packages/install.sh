#!/bin/sh
# Installs the packages listed in the option `packages` with apt-get from the image's repositories, to the paths the
# packages define. Runs as root at image build time; the options arrive as PACKAGES, INSTALLRECOMMENDS, REFRESHPOLICY,
# CLEANUP, and NETWORKTIMEOUT.
# POSIX sh, because an empty list must succeed, and a missing apt-get be reported, on images that ship no bash.
set -eu

# Package configuration questions take their default answers: an image build has no terminal to ask on.
export DEBIAN_FRONTEND=noninteractive
readonly DEBIAN_FRONTEND

PACKAGES="${PACKAGES-}"
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
REFRESHPOLICY="${REFRESHPOLICY-default}"
CLEANUP="${CLEANUP-all}"
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"

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

# Runs apt-get with the arguments given, and with the option networkTimeout, unless it is empty, as APT's HTTP and
# HTTPS timeout.
apt_network() {
  if [ -n "${NETWORKTIMEOUT}" ]; then
    apt-get --option "Acquire::http::Timeout=${NETWORKTIMEOUT}" \
      --option "Acquire::https::Timeout=${NETWORKTIMEOUT}" "$@"
  else
    apt-get "$@"
  fi
}

validate_options() {
  case "${INSTALLRECOMMENDS}" in
    true | false) ;;
    *) fail "option installRecommends is \"${INSTALLRECOMMENDS}\"; use true or false" ;;
  esac
  readonly INSTALLRECOMMENDS
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
  if [ "${REFRESHPOLICY}" = never ] && ! has_index; then
    fail "refreshPolicy=never needs a package index in ${lists_dir};" \
      "add it to the image, or use refreshPolicy=default"
  fi
  if [ "${REFRESHPOLICY}" != always ] && has_index; then
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

# Installs the entries given, each as one argument after --.
install_packages() {
  log "installing $* from the image's repositories (installRecommends=${INSTALLRECOMMENDS})"
  # apt-get removes no package, installs no suggested package, matches no entry as a pattern, and keeps a
  # configuration file that the image changed.
  apt_network install --yes --no-remove \
    --option "APT::Install-Recommends=${INSTALLRECOMMENDS}" \
    --option APT::Install-Suggests=false \
    --option APT::Cmd::Pattern-Only=true \
    --option Dpkg::Options::=--force-confdef \
    --option Dpkg::Options::=--force-confold \
    -- "$@" \
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

  # The spec fixes the place of two checks that the guide would put before this point: apt-get is required only for a
  # list that names a package, and exact names can be checked only against the index that refresh_index selects.
  require_apt_get
  resolve_lists_dir
  refresh_index
  check_names "$@"
  install_packages "$@"
  clean_caches
}

main "$@"
