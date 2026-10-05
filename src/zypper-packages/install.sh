#!/bin/sh
# Installs native package entries from the image's enabled repositories. Runs as root at build time.
set -eu
PACKAGES="${PACKAGES:-}"

fail() {
  printf "zypper-packages: %s\n" "$1" >&2
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
  name=${1%%[=<>]*}
  qualifier=${1#"$name"}
  case $name in
    "" | [!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]* | *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-]*)
      fail "refusing the entry '$1': use a package name with an optional version operator."
      ;;
  esac
  case $qualifier in
    "") ;;
    '<='* | '>='*) qualifier=${qualifier#??} ;;
    '='* | '<'* | '>'*) qualifier=${qualifier#?} ;;
  esac
  case $qualifier in
    *[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+~^:-]*) fail "refusing the entry '$1': invalid version." ;;
  esac
  [ "$name" = "$1" ] || [ -n "$qualifier" ] || fail "refusing the entry '$1': empty version."
  case $1 in *.rpm) fail "refusing the entry '$1': RPM files are not accepted." ;; esac
}

describe_system() {
  system=
  if [ -r /etc/os-release ]; then
    system=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d "\"'") || system=
  fi
  printf '%s' "${system:-an unidentified distribution}"
}

# Validate controls before package-manager calls, cache creation, and the empty-list exit.
INSTALLRECOMMENDS="${INSTALLRECOMMENDS-false}"
case $INSTALLRECOMMENDS in true | false) ;; *) fail "installRecommends must be true or false." ;; esac
REFRESHPOLICY="${REFRESHPOLICY-default}"
case $REFRESHPOLICY in default | always | never) ;; *) fail "refreshPolicy must be one of: default, always, never." ;; esac
CLEANUP="${CLEANUP-all}"
case $CLEANUP in all | packages | none) ;; *) fail "cleanup must be one of: all, packages, none." ;; esac

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
  echo "zypper-packages: no packages listed; nothing to do."
  exit 0
fi

if ! command -v zypper >/dev/null 2>&1; then
  fail "zypper was not found on this image ($(describe_system)). This feature supports openSUSE images, which provide zypper."
fi

if [ "$REFRESHPOLICY" = never ]; then
  # Resolve the configured cache root before any operation that might bootstrap
  # metadata. ZYPP_CONF remains inherited; no setting is persisted or sourced.
  config=${ZYPP_CONF-/etc/zypp/zypp.conf}
  cache_root=/var/cache/zypp
  raw_dir=
  if [ -r "$config" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case $line in *=*) ;; *) continue ;; esac
      setting=${line%%=*}
      trim "$setting"
      case $trimmed in
        cachedir)
          trim "${line#*=}"
          [ -z "$trimmed" ] || cache_root=$trimmed
          ;;
        metadatadir)
          trim "${line#*=}"
          raw_dir=$trimmed
          ;;
      esac
    done < "$config"
  fi
  [ -n "$raw_dir" ] || raw_dir=$cache_root/raw
  repos=$(zypper --xmlout --non-interactive --no-refresh repos)
  aliases=$(printf '%s\n' "$repos" | sed -n '/<repo .*enabled="1"/s/.*alias="\([^"]*\)".*/\1/p')
  [ -n "$aliases" ] || fail "refreshPolicy=never requires enabled repositories with usable cached metadata."
  while IFS= read -r alias; do
    [ -s "$raw_dir/$alias/repodata/repomd.xml" ] || [ -s "$raw_dir/$alias/content" ] || fail "refreshPolicy=never requires usable cached metadata for '$alias'."
  done <<EOF
$aliases
EOF
  # With raw metadata present, native build-only validates every repository cache
  # before installation and can rebuild a missing parsed cache without refreshing.
  zypper --non-interactive --no-refresh refresh --build-only
else
  # A separate strict refresh fails before installation if any repository fails.
  zypper --non-interactive refresh
fi
case $INSTALLRECOMMENDS in true) recommends=--recommends ;; false) recommends=--no-recommends ;; esac
zypper --non-interactive --no-refresh install "$recommends" -- "$@"
case $CLEANUP in
  all) zypper --non-interactive clean --all ;;
  packages) zypper --non-interactive clean ;;
  none) ;;
esac
