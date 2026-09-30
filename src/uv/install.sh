#!/bin/sh
# Installs Astral's uv (uv and uvx) into /usr/local/bin, optionally installs Python command-line
# tools with it into /usr/local/share/uv, and prepares the mount point of the per-dev-container
# volume at /var/lib/uv. Runs as root at image build time; options arrive as VERSION and
# TOOLSTOINSTALL. Installing twice is safe: the same release is not downloaded again, another
# release replaces uv and uvx, and tools from both installs stay installed.
# POSIX sh, because Alpine ships no bash.
set -eu

VERSION="${VERSION:-latest}"
TOOLSTOINSTALL="${TOOLSTOINSTALL:-}"

RELEASES_URL="https://github.com/astral-sh/uv/releases"
# The first release that checks the hashes a package index supplies (needed for toolsToInstall).
MIN_TOOLS_VERSION="0.12.16"
BIN_DIR="/usr/local/bin"
VOLUME_DIR="/var/lib/uv"
SHARE_DIR="/usr/local/share/uv"
PROFILE_SNIPPET="/etc/profile.d/uv.sh"

RELEASE_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
# A package name, at most one bracketed extra, at most one version constraint, and no whitespace;
# with ARCHIVE_RE, nothing that uv could read as an option, a URL, or a path.
NAME_RE='[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?'
TOOL_RE="^${NAME_RE}(\\[${NAME_RE}\\])?((==|~=|!=|>=|<=|>|<|@)[A-Za-z0-9][A-Za-z0-9.*+!_-]*)?\$"
# A package name that ends in a wheel or source-archive suffix, which uv reads as a path to a local
# file (checked lower-cased, on the name without extra or constraint).
ARCHIVE_RE='\.(whl|zip|tgz|tbz|txz|tar|tar\.(gz|bz2|xz|lz|lzma|zst))$'
NL='
'

log() {
    echo "uv feature: $*"
}

fail() {
    # "$*" joins with the first character of IFS, which the option parsing changes.
    IFS=' '
    echo "uv feature: error: $*" >&2
    exit 1
}

# Whether $1, a single line, matches the extended regular expression $2.
matches() {
    case "$1" in
        *"$NL"*) return 1 ;;
    esac
    printf '%s\n' "$1" | grep -Eq "$2"
}

# Whether release $1 is older than release $2 (both MAJOR.MINOR.PATCH).
older_than() {
    a_major=${1%%.*}
    a_patch=${1##*.}
    a_minor=${1#*.}
    a_minor=${a_minor%.*}
    b_major=${2%%.*}
    b_patch=${2##*.}
    b_minor=${2#*.}
    b_minor=${b_minor%.*}
    [ "$a_major" -ne "$b_major" ] && { [ "$a_major" -lt "$b_major" ]; return; }
    [ "$a_minor" -ne "$b_minor" ] && { [ "$a_minor" -lt "$b_minor" ]; return; }
    [ "$a_patch" -lt "$b_patch" ]
}

# Sets TRIMMED to $1 without leading and trailing whitespace.
trim() {
    TRIMMED=$1
    while :; do
        case "$TRIMMED" in
            [[:space:]]*) TRIMMED=${TRIMMED#?} ;;
            *) break ;;
        esac
    done
    while :; do
        case "$TRIMMED" in
            *[[:space:]]) TRIMMED=${TRIMMED%?} ;;
            *) break ;;
        esac
    done
}

# --- Validate the options before any download or file change ---------------------------------

if [ "$VERSION" != "latest" ] && ! matches "$VERSION" "$RELEASE_RE"; then
    fail "version '$VERSION' is neither 'latest' nor a release as MAJOR.MINOR.PATCH."
fi

# TOOLS holds the validated entries separated by newlines; an entry never contains whitespace.
TOOLS=""
set -f
old_ifs=$IFS
IFS=,
for raw in $TOOLSTOINSTALL; do
    trim "$raw"
    [ -n "$TRIMMED" ] || continue
    if ! matches "$TRIMMED" "$TOOL_RE"; then
        fail "toolsToInstall entry '$TRIMMED' is not a package name with at most one bracketed extra and one" \
            "version constraint (==, ~=, !=, >=, <=, >, <, or @ followed by a version)."
    fi
    tool_name=$(printf '%s\n' "$TRIMMED" | sed 's/[^A-Za-z0-9._-].*//' | tr '[:upper:]' '[:lower:]')
    if matches "$tool_name" "$ARCHIVE_RE"; then
        fail "toolsToInstall entry '$TRIMMED' ends in an archive or wheel suffix, which uv reads as a local" \
            "path, not a package name."
    fi
    TOOLS="${TOOLS}${TRIMMED}${NL}"
done
IFS=$old_ifs
set +f

if [ -n "$TOOLS" ] && [ "$VERSION" != "latest" ] && older_than "$VERSION" "$MIN_TOOLS_VERSION"; then
    fail "toolsToInstall needs uv $MIN_TOOLS_VERSION or later, which checks the hashes the package index" \
        "supplies; version is $VERSION."
fi

# --- Check the platform ------------------------------------------------------------------------

machine=$(uname -m)
case "$machine" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) fail "unsupported architecture '$machine'; this feature supports x86_64 and aarch64." ;;
esac

libc=gnu
for loader in /lib/ld-musl-*.so.1; do
    if [ -e "$loader" ]; then
        libc=musl
    fi
done

[ -r /etc/os-release ] || fail "cannot read /etc/os-release to detect the distribution."
# shellcheck source=/dev/null
os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
# shellcheck source=/dev/null
os_like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
# shellcheck source=/dev/null
os_name=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${ID:-unknown}}")
family=""
case "$os_id" in
    opensuse*) family=zypper ;;
esac
set -f
for word in $os_id $os_like; do
    [ -z "$family" ] || break
    case "$word" in
        debian | ubuntu) family=apt ;;
        rhel | centos | fedora) family=dnf ;;
        arch) family=pacman ;;
        alpine) family=apk ;;
        suse | opensuse) family=zypper ;;
    esac
done
set +f
if [ -z "$family" ]; then
    fail "unsupported distribution '$os_name' (ID=$os_id, ID_LIKE=$os_like); this feature supports Debian- and" \
        "Ubuntu-based, RHEL- and Fedora-based, Arch Linux, Alpine, and openSUSE or SUSE images."
fi

remote_user="${_REMOTE_USER:-root}"
id -u "$remote_user" >/dev/null 2>&1 || fail "the remote user '$remote_user' does not exist in the image."
remote_group=$(id -g "$remote_user")

# --- Prerequisites from the image's own repositories -------------------------------------------

has_ca_bundle() {
    for bundle in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem \
        /etc/ssl/cert.pem; do
        [ -s "$bundle" ] && return 0
    done
    return 1
}

missing=""
command -v curl >/dev/null 2>&1 || missing="$missing curl"
if ! has_ca_bundle; then
    if [ "$family" = zypper ]; then missing="$missing ca-certificates-mozilla"; else missing="$missing ca-certificates"; fi
fi
command -v tar >/dev/null 2>&1 || missing="$missing tar"
command -v sha256sum >/dev/null 2>&1 || missing="$missing coreutils"

if [ -n "$missing" ]; then
    log "installing missing prerequisites with $family:$missing"
    case "$family" in
        apt) manager=apt-get ;;
        pacman) manager=pacman ;;
        *) manager=$family ;;
    esac
    command -v "$manager" >/dev/null 2>&1 || fail "cannot install$missing: $manager is not available."
    # $missing is a list of package names, split on purpose.
    # shellcheck disable=SC2086
    case "$family" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y --no-install-recommends $missing
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            ;;
        dnf)
            dnf install -y --setopt=install_weak_deps=False $missing
            dnf clean all
            ;;
        pacman)
            # Arch supports installing a package only together with a full system upgrade.
            pacman -Syu --needed --noconfirm $missing
            find /var/cache/pacman/pkg -mindepth 1 -delete
            ;;
        apk)
            apk add --no-cache $missing
            ;;
        zypper)
            zypper --non-interactive install --no-recommends $missing
            zypper --non-interactive clean --all
            ;;
    esac
    if ! command -v curl >/dev/null 2>&1 || ! has_ca_bundle || ! command -v tar >/dev/null 2>&1 \
        || ! command -v sha256sum >/dev/null 2>&1; then
        fail "prerequisites are still missing after installing$missing."
    fi
fi

# HTTPS only, on every request and redirect; HTTP errors fail.
fetch() {
    curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --location --retry 3 \
        --output "$2" "$1"
}

# --- Resolve the release -----------------------------------------------------------------------

if [ "$VERSION" = "latest" ]; then
    # Read the redirect without following it; the release name is its last path segment.
    location=$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error --retry 3 --output /dev/null \
        --write-out '%{redirect_url}' "$RELEASES_URL/latest") \
        || fail "could not resolve the latest uv release from $RELEASES_URL/latest."
    release=${location##*/}
    matches "$release" "$RELEASE_RE" \
        || fail "$RELEASES_URL/latest redirected to '$location', which names no MAJOR.MINOR.PATCH release."
    if [ -n "$TOOLS" ] && older_than "$release" "$MIN_TOOLS_VERSION"; then
        fail "toolsToInstall needs uv $MIN_TOOLS_VERSION or later, which checks the hashes the package index" \
            "supplies; the latest release is $release."
    fi
else
    release=$VERSION
fi

tmp=$(mktemp -d)
cleanup() {
    rm -rf "$tmp"
    rm -f "$BIN_DIR/.uv.new" "$BIN_DIR/.uvx.new"
}
trap cleanup EXIT

# --- Install uv and uvx ------------------------------------------------------------------------

installed=""
if [ -x "$BIN_DIR/uv" ] && [ -x "$BIN_DIR/uvx" ]; then
    uv_version=$("$BIN_DIR/uv" --version 2>/dev/null | cut -d' ' -f2) || uv_version=""
    uvx_version=$("$BIN_DIR/uvx" --version 2>/dev/null | cut -d' ' -f2) || uvx_version=""
    if [ "$uv_version" = "$uvx_version" ]; then
        installed=$uv_version
    fi
fi

if [ "$installed" = "$release" ]; then
    log "uv $release is already installed in $BIN_DIR; nothing to download."
else
    asset="uv-${arch}-unknown-linux-${libc}.tar.gz"
    url="$RELEASES_URL/download/$release/$asset"
    log "downloading $url"
    fetch "$url" "$tmp/$asset" || fail "could not download $asset of uv $release; is $release a published release?"
    fetch "$url.sha256" "$tmp/$asset.sha256" \
        || fail "could not download the checksum of $asset ($url.sha256); nothing was installed."
    expected=$(cut -d' ' -f1 <"$tmp/$asset.sha256" | tr 'A-F' 'a-f')
    matches "$expected" '^[0-9a-f]{64}$' || fail "the checksum file of $asset holds no SHA-256; nothing was installed."
    actual=$(sha256sum "$tmp/$asset" | cut -d' ' -f1)
    [ "$actual" = "$expected" ] \
        || fail "checksum mismatch for $asset: expected $expected, got $actual; nothing was installed."

    tar -xzf "$tmp/$asset" -C "$tmp"
    unpacked="$tmp/uv-${arch}-unknown-linux-${libc}"
    if [ ! -f "$unpacked/uv" ] || [ ! -f "$unpacked/uvx" ]; then
        fail "$asset holds no uv and uvx; nothing was installed."
    fi
    mkdir -p "$BIN_DIR"
    for exe in uv uvx; do
        cp "$unpacked/$exe" "$BIN_DIR/.$exe.new"
        chmod 0755 "$BIN_DIR/.$exe.new"
    done
    mv -f "$BIN_DIR/.uv.new" "$BIN_DIR/uv"
    mv -f "$BIN_DIR/.uvx.new" "$BIN_DIR/uvx"
    log "installed $("$BIN_DIR/uv" --version)"
fi

# --- Directories and login shells --------------------------------------------------------------

# The mount point of the volume: empty and owned by the remote user, so Docker gives a new volume
# that owner. Nothing is ever written below it at build time.
mkdir -p "$VOLUME_DIR"
chown "$remote_user:$remote_group" "$VOLUME_DIR"
chmod 0755 "$VOLUME_DIR"

mkdir -p "$SHARE_DIR/tools" "$SHARE_DIR/python" "$SHARE_DIR/bin"

mkdir -p "$(dirname "$PROFILE_SNIPPET")"
cat >"$PROFILE_SNIPPET" <<'EOF'
# Written by the uv Dev Container Feature on every install; edits are overwritten.
# Keeps uv's tool executables on PATH in login shells whose profile resets PATH.
case ":${PATH}:" in
    *:/usr/local/share/uv/bin:*) ;;
    *) PATH="/usr/local/share/uv/bin${PATH:+:${PATH}}"; export PATH ;;
esac
EOF
chown root:root "$PROFILE_SNIPPET"
chmod 0644 "$PROFILE_SNIPPET"

# --- Build-time tools ---------------------------------------------------------------------------

if [ -n "$TOOLS" ]; then
    # Interpreters in the image, not on the volume; a cache that goes away with this install; uv's
    # default sources and checks, so no index, mirror, or hash setting is passed.
    mkdir -p "$tmp/cache"
    set -f
    for tool in $TOOLS; do
        log "installing tool $tool"
        UV_PYTHON_INSTALL_DIR="$SHARE_DIR/python" UV_CACHE_DIR="$tmp/cache" UV_MANAGED_PYTHON=1 \
            UV_TOOL_DIR="$SHARE_DIR/tools" UV_TOOL_BIN_DIR="$SHARE_DIR/bin" \
            "$BIN_DIR/uv" tool install "$tool" || fail "uv tool install could not install '$tool'."
    done
    set +f
fi

# The remote user manages tools at runtime with uv tool, without elevated privileges.
chown -hR "$remote_user:$remote_group" "$SHARE_DIR"

log "done: $("$BIN_DIR/uv" --version)"
