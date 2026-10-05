#!/bin/sh
# Installs the packages named in the `packages` option (PACKAGES) with apk, from the repositories
# the image already configures, and configures nothing else. Runs as root at image build time.
# POSIX sh so the package installers share one skeleton: parse, validate, the empty check, the
# package-manager check, refresh, install, clean. A second run installs its own list the same way
# (openspec/specs/apk-packages/spec.md, "Installing the feature twice").
set -eu

# Entries are matched as bytes, so no pattern below can admit a non-ASCII letter.
locale_was_set=${LC_ALL+yes}
locale_before=${LC_ALL-}
LC_ALL=C
export LC_ALL

PACKAGES="${PACKAGES:-}"

fail() {
  printf 'apk-packages: %s\n' "$1" >&2
  exit 1
}

# Sets $trimmed to $1 without leading and trailing whitespace.
trim() {
  trimmed=$1
  while :; do
    case $trimmed in
      [[:space:]]*) trimmed=${trimmed#?} ;;
      *) break ;;
    esac
  done
  while :; do
    case $trimmed in
      *[[:space:]]) trimmed=${trimmed%?} ;;
      *) break ;;
    esac
  done
}

refuse() {
  fail "refusing the entry '$1': an entry starts with an ASCII letter or digit and holds only ASCII letters, digits, and the characters . _ + - : ~ = @ < > (a package or provided name, optionally followed by a version constraint or '@tag'). Paths, URLs, options, conflict markers ('!'), patterns, whitespace, and other shell characters are not accepted."
}

# Accepts $1 only when it matches ^[A-Za-z0-9][A-Za-z0-9._+:~=@<>-]*$. The character sets are
# spelled out instead of written as ranges, so the match does not depend on how a shell reads a range.
check_entry() {
  case $1 in
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*) refuse "$1" ;;
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+:~=@\<\>-]*) refuse "$1" ;;
  esac
}

describe_system() {
  system=
  if [ -r /etc/os-release ]; then
    system=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d "\"'") || system=
  fi
  printf '%s' "${system:-an unidentified distribution}"
}

# Removes the two directories the feature created; nothing else of the feature's is in the image.
cache_dir=
work_dir=
remove_temporary_dirs() {
  cd /
  [ "$CLEANUP" != all ] || [ -z "$cache_dir" ] || rm -rf -- "$cache_dir"
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
}


# Validate controls before package-manager calls, cache creation, and the empty-list exit.
REFRESHPOLICY="${REFRESHPOLICY-default}"
case $REFRESHPOLICY in default | always | never) ;; *) fail "refreshPolicy must be one of: default, always, never." ;; esac
CLEANUP="${CLEANUP-all}"
case $CLEANUP in all | packages | none) ;; *) fail "cleanup must be one of: all, packages, none." ;; esac
NETWORKTIMEOUT="${NETWORKTIMEOUT-}"
case $NETWORKTIMEOUT in
  "") ;;
  0* | *[!0123456789]*) fail "networkTimeout must be empty or an integer from 1 through 3600 without leading zeros." ;;
  *)
    if [ "${#NETWORKTIMEOUT}" -gt 4 ] || [ "$NETWORKTIMEOUT" -gt 3600 ]; then
      fail "networkTimeout must be from 1 through 3600."
    fi
    ;;
esac
UPGRADEPACKAGES="${UPGRADEPACKAGES-false}"
case $UPGRADEPACKAGES in true | false) ;; *) fail "upgradePackages must be true or false." ;; esac

# Parse and validate every entry before anything else happens; accepted entries become "$@", so each
# reaches apk as one argument and none is ever evaluated as shell code.
set --
rest="$PACKAGES,"
while [ -n "$rest" ]; do
  entry=${rest%%,*}
  rest=${rest#*,}
  trim "$entry"
  [ -n "$trimmed" ] || continue
  check_entry "$trimmed"
  set -- "$@" "$trimmed"
done

if [ -n "$locale_was_set" ]; then LC_ALL=$locale_before; else unset LC_ALL; fi

if [ "$#" -eq 0 ]; then
  echo "apk-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v apk >/dev/null 2>&1; then
  fail "apk was not found on this image ($(describe_system)). This feature supports Alpine Linux images, which provide apk."
fi

trap remove_temporary_dirs EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# A fresh work directory prevents package entries from resolving to local files.
# Retained indexes are feature-owned; image caches are only read, never cleaned.
if [ "$CLEANUP" = all ]; then
  cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/apk-packages.XXXXXX")
else
  cache_dir=/var/cache/apk-packages
  mkdir -p "$cache_dir"
fi
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/apk-packages.XXXXXX")
cd "$work_dir"

apk_network() {
  if [ -n "$NETWORKTIMEOUT" ]; then
    apk --timeout "$NETWORKTIMEOUT" "$@"
  else
    apk "$@"
  fi
}

if [ "$REFRESHPOLICY" = never ]; then
  # Copy missing indexes from native image caches. apk itself verifies repository
  # coverage and signatures offline before any add; a cache miss cannot fetch an index.
  for source_dir in /var/cache/apk /etc/apk/cache /var/cache/apk-packages; do
    [ "$source_dir" != "$cache_dir" ] || continue
    for index in "$source_dir"/APKINDEX.*.tar.gz "$source_dir"/*.adb; do
      [ -f "$index" ] || continue
      [ -e "$cache_dir/${index##*/}" ] || cp -p "$index" "$cache_dir/"
    done
  done
  apk_network update --no-network --no-interactive --cache-dir "$cache_dir" || fail "refreshPolicy=never requires usable cached indexes for every repository."
else
  echo "apk-packages: fetching the index of every configured repository"
  apk_network update --no-interactive --cache-dir "$cache_dir" || {
    status=$?
    printf 'apk-packages: apk update failed (exit %s): every repository must be fetched and verified before installation.\n' "$status" >&2
    exit "$status"
  }
fi

# Offline verification above establishes every cached index; the large age limit
# prevents add from checking remote indexes while still permitting package downloads.
set -- -- "$@"
[ "$UPGRADEPACKAGES" = false ] || set -- --upgrade "$@"
echo "apk-packages: installing $*"
apk_network add --no-interactive --cache-dir "$cache_dir" --cache-max-age 35791394 "$@"

case $CLEANUP in
  all) rm -rf /var/cache/apk-packages ;;
  packages) rm -f "$cache_dir"/*.apk ;;
  none) ;;
esac
