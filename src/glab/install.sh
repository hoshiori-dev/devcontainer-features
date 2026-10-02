#!/bin/sh
# Installs the GitLab CLI (glab) from its GitLab release archive, verified against the release's
# checksums.txt, to /usr/local/bin/glab. Runs as root at image build time; the `version` option
# arrives as VERSION. Configures no authentication and writes nothing under any home directory.
# Installing twice is safe: the requested version, when already installed, is left untouched, and
# any other version is replaced atomically, so a failed install keeps the earlier binary.
# POSIX sh, because Alpine ships no bash.
set -eu

MIN_VERSION="1.47.0"
RELEASES="https://gitlab.com/gitlab-org/cli/-/releases"
TARGET="/usr/local/bin/glab"
FAMILIES="the Debian, Ubuntu, Fedora, and Alpine families"
REQUESTED="${VERSION-latest}"

work=""
staged=""
cleanup() {
  if [ -n "$staged" ]; then rm -f "$staged"; fi
  if [ -n "$work" ]; then rm -rf "$work"; fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

log() {
  echo "glab feature: $*"
}

fail() {
  echo "glab feature: error: $*" >&2
  exit 1
}

# Prints $1 without a leading "v" when it is v?MAJOR.MINOR.PATCH of decimal numbers; else returns 1.
normalize_version() {
  v=${1#v}
  case $v in
    *.*.*.*) return 1 ;;
    *.*.*) ;;
    *) return 1 ;;
  esac
  major=${v%%.*}
  rest=${v#*.}
  minor=${rest%%.*}
  patch=${rest#*.}
  for part in "$major" "$minor" "$patch"; do
    case $part in
      '' | *[!0-9]*) return 1 ;;
    esac
  done
  printf '%s\n' "$v"
}

# Succeeds when normalized version $1 is at or above normalized version $2.
version_at_least() {
  a=$1
  b=$2
  for _ in 1 2 3; do
    x=${a%%.*}
    y=${b%%.*}
    if [ "$x" -gt "$y" ]; then return 0; fi
    if [ "$x" -lt "$y" ]; then return 1; fi
    a=${a#*.}
    b=${b#*.}
  done
  return 0
}

# Every request goes over HTTPS only, including each redirect; failing HTTP statuses are errors.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 "$@"
}

# Downloads $1 to $2, following redirects, and logs the final URL so a host change shows in the log.
download() {
  final=$(fetch --location --output "$2" --write-out '%{url_effective}' "$1") || return 1
  log "downloaded $1 (final URL: $final)"
}

# Runs a glab binary isolated from the image: temporary configuration, no update check, no telemetry.
run_glab() {
  binary=$1
  shift
  GLAB_CONFIG_DIR="$work/config" GLAB_CHECK_UPDATE=false CHECK_UPDATE=false \
    GLAB_SEND_TELEMETRY=false "$binary" "$@"
}

# Succeeds when binary $1 reports version $2 in an output format glab has used since 1.47.0.
reports_version() {
  output=$(run_glab "$1" --version 2>/dev/null) || return 1
  case $output in
    "glab $2 ("* | "Current glab version: $2" | "Current glab version: $2 ("*) return 0 ;;
  esac
  return 1
}

has_package() {
  case $pm in
    apt-get) dpkg-query -W -f '${Status}' "$1" 2>/dev/null | grep -q 'install ok installed' ;;
    dnf) rpm -q "$1" >/dev/null 2>&1 ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
  esac
}

# --- Checks that need no network, before anything is installed or downloaded ---

version=""
if [ "$REQUESTED" != "latest" ]; then
  if ! version=$(normalize_version "$REQUESTED"); then
    fail "invalid version '$REQUESTED': use 'latest' or a release version MAJOR.MINOR.PATCH," \
      "with or without a leading 'v' (for example 1.120.0)."
  fi
  version_at_least "$version" "$MIN_VERSION" \
    || fail "version $version is not supported: the minimum is $MIN_VERSION."
fi

machine=$(uname -m)
case $machine in
  x86_64) arch=amd64 ;;
  aarch64) arch=arm64 ;;
  *) fail "unsupported architecture '$machine': supported are x86_64 and aarch64." ;;
esac

[ -f /etc/os-release ] \
  || fail "/etc/os-release is missing, so the distribution cannot be identified; supported are $FAMILIES."
# Read in subshells: os-release sets VERSION, which would overwrite the option.
# shellcheck source=/dev/null
os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
# shellcheck source=/dev/null
os_like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
pm=""
set -f
for word in $os_id $os_like; do
  case $word in
    debian | ubuntu) pm=apt-get ;;
    fedora) pm=dnf ;;
    alpine) pm=apk ;;
    *) continue ;;
  esac
  break
done
set +f
[ -n "$pm" ] \
  || fail "unsupported distribution '$os_id' (ID_LIKE '$os_like'): supported are $FAMILIES."
command -v "$pm" >/dev/null 2>&1 \
  || fail "distribution '$os_id' is in a supported family, but its package manager $pm is missing."

# --- Prerequisites: git for glab at run time; curl, ca-certificates, and tar for the install ---

missing=""
for command in git curl tar; do
  command -v "$command" >/dev/null 2>&1 || missing="$missing $command"
done
has_package ca-certificates || missing="$missing ca-certificates"
if [ -n "$missing" ]; then
  log "installing missing prerequisites:$missing"
  # $missing is a space-separated list of package names, split on purpose.
  case $pm in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update
      # shellcheck disable=SC2086
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $missing
      rm -rf /var/lib/apt/lists/*
      ;;
    dnf)
      # shellcheck disable=SC2086
      dnf install -y $missing
      dnf clean all
      ;;
    apk)
      # shellcheck disable=SC2086
      apk add --no-cache $missing
      ;;
  esac
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/glab-feature.XXXXXX")
mkdir -m 700 "$work/config"

# --- Version: `latest` from the release page's permanent link, read without following it ---

if [ -z "$version" ]; then
  location=$(fetch --head --output /dev/null --write-out '%{redirect_url}' "$RELEASES/permalink/latest") \
    || fail "could not read $RELEASES/permalink/latest."
  [ -n "$location" ] || fail "$RELEASES/permalink/latest did not redirect to a release."
  tag=${location%%[?#]*}
  tag=${tag%/}
  tag=${tag##*/}
  log "latest release: $location"
  if ! version=$(normalize_version "$tag"); then
    fail "the latest release is '$tag', which is not a release version MAJOR.MINOR.PATCH;" \
      "set the version option to a release."
  fi
  version_at_least "$version" "$MIN_VERSION" \
    || fail "the latest release is '$tag', below the minimum $MIN_VERSION."
fi

if [ -f "$TARGET" ] && reports_version "$TARGET" "$version"; then
  log "glab $version is already installed at $TARGET; leaving it unchanged."
  exit 0
fi

# --- Download and verify against the release's checksums.txt ---

archive="glab_${version}_linux_${arch}.tar.gz"
downloads="$RELEASES/v$version/downloads"
if ! download "$downloads/checksums.txt" "$work/checksums.txt"; then
  fail "could not download checksums.txt of glab $version from $downloads/checksums.txt;" \
    "does release v$version exist?"
fi
awk -v name="$archive" 'NF == 2 && $2 == name' "$work/checksums.txt" >"$work/archive.sha256"
entries=$(awk 'END { print NR }' "$work/archive.sha256")
[ "$entries" = 1 ] \
  || fail "verification failed: checksums.txt holds $entries entries for $archive, expected exactly one."
download "$downloads/$archive" "$work/$archive" \
  || fail "could not download $archive of glab $version from $downloads/$archive."
(cd "$work" && sha256sum -c archive.sha256) \
  || fail "verification failed: the SHA-256 digest of $archive does not match its entry in checksums.txt."

mkdir "$work/extract"
tar -xzf "$work/$archive" -C "$work/extract" bin/glab \
  || fail "could not extract bin/glab from $archive."
if [ ! -f "$work/extract/bin/glab" ] || [ -L "$work/extract/bin/glab" ]; then
  fail "$archive does not hold bin/glab as a regular file."
fi

# --- Install: stage next to the target, then rename over it atomically ---

mkdir -p "${TARGET%/*}"
staged=$(mktemp "${TARGET%/*}/.glab-feature.XXXXXX")
cp "$work/extract/bin/glab" "$staged"
chmod 0755 "$staged"
mv -f "$staged" "$TARGET"
staged=""
log "installed $(run_glab "$TARGET" --version 2>/dev/null || echo "glab $version") at $TARGET"
