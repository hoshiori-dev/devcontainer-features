#!/bin/sh
# Installs the packages named in the `packages` option (PACKAGES) with apk, from the repositories
# the image already configures, and configures nothing else. Runs as root at image build time.
# POSIX sh so the package installers share one skeleton: parse, validate, the empty check, the
# package-manager check, refresh, install, clean. A second run installs its own list the same way
# (openspec/specs/apk-packages/spec.md, "Installing the feature twice").
set -eu

# Entries are matched as bytes, so no pattern below can admit a non-ASCII letter.
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
cleanup() {
  cd /
  [ -z "$cache_dir" ] || rm -rf -- "$cache_dir"
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
}

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

if [ "$#" -eq 0 ]; then
  echo "apk-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v apk >/dev/null 2>&1; then
  fail "apk was not found on this image ($(describe_system)). This feature supports Alpine Linux images, which provide apk."
fi

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Both directories are new: the cache directory holds only what this run fetches, and the working
# directory stays empty, so apk cannot read an entry as a local package file.
cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/apk-packages.XXXXXX")
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/apk-packages.XXXXXX")
cd "$work_dir"

# apk update exits 0 only when the index of every configured repository was fetched and verified;
# apk add alone would skip a failing repository and install from the others.
echo "apk-packages: fetching the index of every configured repository"
apk update --no-interactive --cache-dir "$cache_dir" || {
  status=$?
  printf 'apk-packages: apk update failed (exit %s): the index of every configured repository must be fetched and verified before anything is installed.\n' "$status" >&2
  exit "$status"
}

echo "apk-packages: installing $*"
apk add --no-interactive --cache-dir "$cache_dir" -- "$@"
