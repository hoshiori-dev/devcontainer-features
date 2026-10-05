#!/bin/sh
# Installs the packages named in the `packages` option (PACKAGES) with apt-get, from the repositories
# the image already configures, and configures nothing else. Runs as root at image build time.
# POSIX sh so the package installers share one skeleton: parse, validate, the empty check, the
# package-manager check, refresh when no index exists, install, clean. A second run installs its own
# list the same way (openspec/specs/apt-packages/spec.md, "Installing the feature twice").
set -eu

PACKAGES="${PACKAGES:-}"

fail() {
  printf 'apt-packages: %s\n' "$1" >&2
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
  fail "refusing the entry '$1': an entry is a package name (lower-case letters, digits, '.', '+', '-', starting with a letter or digit), optionally followed by ':architecture' or '=version' (letters, digits, '.', '+', '-', ':', '~', '='), and does not end in '-'. Paths, URLs, options, patterns, and shell characters are not accepted."
}

# Accepts $1 only when it matches ^[a-z0-9][a-z0-9.+-]*([:=][A-Za-z0-9.+:~=-]*)?$ and does not end in
# '-'. The character sets are spelled out instead of written as ranges, which some shells read by
# locale collation.
check_entry() {
  name=${1%%[=:]*}
  qualifier=${1#"$name"}
  case $name in
    "" | [!abcdefghijklmnopqrstuvwxyz0123456789]* | *[!abcdefghijklmnopqrstuvwxyz0123456789.+-]*)
      refuse "$1"
      ;;
  esac
  case $qualifier in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+:~=-]*) refuse "$1" ;;
  esac
  case $1 in
    *-) refuse "$1" ;;
  esac
}

describe_system() {
  system=
  if [ -r /etc/os-release ]; then
    system=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d "\"'") || system=
  fi
  printf '%s' "${system:-an unidentified distribution}"
}

has_index() {
  for list in "$lists_dir"/*_Packages*; do
    [ -e "$list" ] && return 0
  done
  return 1
}


# Validate controls before package-manager calls, cache creation, and the empty-list exit.
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
case $INSTALLRECOMMENDS in true | false) ;; *) fail "installRecommends must be true or false." ;; esac
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

# Parse and validate every entry before anything else happens; accepted entries become "$@", so each
# reaches apt-get as one argument and none is ever evaluated as shell code.
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

if [ "$#" -eq 0 ]; then
  echo "apt-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  fail "apt-get was not found on this image ($(describe_system)). This feature supports Debian and Ubuntu images, which provide apt-get."
fi

# apt-config resolves inherited APT_CONFIG and Dir overrides; its shell output is data,
# never sourced. An empty/root list directory must not become an unbounded cleanup target.
lists_dir=$(apt-config shell value Dir::State::lists/d | sed "s/^value='//; s/'$//")
case $lists_dir in "" | /) fail "APT's effective package index directory must not be empty or root." ;; esac

apt_network() {
  if [ -n "$NETWORKTIMEOUT" ]; then
    apt-get -o "Acquire::http::Timeout=$NETWORKTIMEOUT" -o "Acquire::https::Timeout=$NETWORKTIMEOUT" "$@"
  else
    apt-get "$@"
  fi
}

case $REFRESHPOLICY in
  always) apt_network update --error-on=any ;;
  never) has_index || fail "refreshPolicy=never requires a usable cached package index." ;;
  default)
    if has_index; then
      echo "apt-packages: using the package index the image already holds."
    else
      apt_network update --error-on=any
    fi
    ;;
esac

# APT treats a trailing '+' on an unknown name or version as an install marker. Check exact names
# (including virtual packages) and version fields before installing any entry; real names such as
# g++ remain valid. These lookups use the index selected above and never refresh it themselves.
for entry do
  name=${entry%%[=:]*}
  if ! apt-cache pkgnames --all-names "$name" | grep -Fxq -- "$name"; then
    fail "no exact package name for the entry '$entry'."
  fi
  case $entry in
    *=*)
      version=${entry#*=}
      if ! apt-cache show -- "$entry" | awk -v version="$version" '
        $1 == "Version:" && $2 == version { found = 1 }
        END { exit !found }
      '; then
        fail "no exact package version for the entry '$entry'."
      fi
      ;;
  esac
done

echo "apt-packages: installing $*"
DEBIAN_FRONTEND=noninteractive apt_network install -y --no-remove \
  -o "APT::Install-Recommends=$INSTALLRECOMMENDS" \
  -o APT::Install-Suggests=false \
  -o APT::Cmd::Pattern-Only=true \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  -- "$@"

case $CLEANUP in
  all) apt-get clean; rm -rf "${lists_dir:?}"/* ;;
  packages) apt-get clean ;;
  none) ;;
esac
