#!/bin/sh
# Installs native package entries from the image's enabled repositories. Runs as root at build time.
set -eu
PACKAGES="${PACKAGES:-}"

fail() {
  printf "dnf-packages: %s\n" "$1" >&2
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

check_entry() {
  case $1 in
    [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+:~^-]* | *.[rR][pP][mM])
      fail "refusing the entry '$1': use a package name, version, or architecture; paths, RPM files, options, patterns, and shell characters are not accepted."
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
INSTALLWEAKDEPS="${INSTALLWEAKDEPS-false}"
case $INSTALLWEAKDEPS in true | false) ;; *) fail "installWeakDeps must be true or false." ;; esac
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
  echo "dnf-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v dnf >/dev/null 2>&1; then
  fail "dnf was not found on this image ($(describe_system)). This feature requires dnf on Fedora or RHEL-compatible images; images with only microdnf are not supported."
fi

# Build a quoted native argument list without changing inherited configuration.
set -- -- "$@"
case $REFRESHPOLICY in
  always) set -- --refresh '--setopt=*.skip_if_unavailable=False' "$@" ;;
  never) set -- --cacheonly '--setopt=*.skip_if_unavailable=False' "$@" ;;
esac
if [ -n "$NETWORKTIMEOUT" ]; then
  set -- "--setopt=timeout=$NETWORKTIMEOUT" "--setopt=*.timeout=$NETWORKTIMEOUT" "$@"
fi
case $INSTALLWEAKDEPS in true) weak=True ;; false) weak=False ;; esac
dnf install -y "--setopt=install_weak_deps=$weak" "$@"
case $CLEANUP in
  all) dnf clean all ;;
  packages) dnf clean packages ;;
  none) ;;
esac
