#!/bin/sh
# Installs the packages named in the `packages` option (PACKAGES) with pacman, from the repositories
# the image already configures, as part of a full system upgrade, and configures nothing else. Runs
# as root at image build time. POSIX sh so the package installers share one skeleton: parse,
# validate, the empty check, the package-manager check, install (pacman synchronizes the databases
# in the same call), clean. A second run does the same with its own list
# (openspec/specs/pacman-packages/spec.md, "Installing the feature twice").
set -eu

PACKAGES="${PACKAGES:-}"

fail() {
  printf 'pacman-packages: %s\n' "$1" >&2
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
  fail "refusing the entry '$1': an entry is a package name, a provided name, or a group (ASCII letters, digits, '@', '.', '_', '+', '-', starting with a letter or digit), optionally followed by a version constraint ('=', '<', '<=', '>', or '>=' and a version, which may hold ':'). Paths, URLs, 'repository/name', options, patterns, and shell characters are not accepted."
}

# Accepts $1 only when it matches ^[A-Za-z0-9][A-Za-z0-9@._+:<>=-]*$. The character sets are spelled
# out instead of written as ranges, which some shells read by locale collation.
check_entry() {
  case $1 in
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | \
      *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+:\<\>=-]*)
      refuse "$1"
      ;;
  esac
}

describe_system() {
  system=
  if [ -r /etc/os-release ]; then
    system=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d "\"'") || system=
  fi
  printf '%s' "${system:-an unidentified distribution}"
}


# Validate controls before package-manager calls, cache creation, and the empty-list exit.
CLEANUP="${CLEANUP-all}"
case $CLEANUP in all | packages | none) ;; *) fail "cleanup must be one of: all, packages, none." ;; esac

# Parse and validate every entry before anything else happens; accepted entries become "$@", so each
# reaches pacman as one argument and none is ever evaluated as shell code. The check runs in the C
# locale, where a bracket expression matches single bytes and so no non-ASCII letter; the locale the
# build set is restored afterwards, so pacman and the packages' install scripts run in it.
locale_was_set=${LC_ALL+yes}
locale_before=${LC_ALL-}
LC_ALL=C
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
if [ -n "$locale_was_set" ]; then
  LC_ALL=$locale_before
else
  unset LC_ALL
fi

if [ "$#" -eq 0 ]; then
  echo "pacman-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v pacman >/dev/null 2>&1; then
  fail "pacman was not found on this image ($(describe_system)). This feature supports Arch Linux images, which provide pacman."
fi

# One transaction: synchronize every database, upgrade the system (Arch Linux supports no partial
# upgrade), and install the list. --needed skips a listed package that is already up to date, and
# --noconfirm takes pacman's default answer to every question.
echo "pacman-packages: upgrading the system and installing $*"
pacman -Syu --needed --noconfirm -- "$@"

# Deleted directly: `pacman -Scc` asks before it removes, and under --noconfirm the answer is no.
case $CLEANUP in
  all) rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* ;;
  packages) rm -rf /var/cache/pacman/pkg/* ;;
  none) ;;
esac
