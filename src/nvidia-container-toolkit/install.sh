#!/usr/bin/env bash
# Installs the NVIDIA Container Toolkit from NVIDIA's stable package repository, trusting only NVIDIA's
# signing key pinned by its full fingerprint, and registers the nvidia runtime with a Docker daemon
# installed in the image. Runs as root at image build time; options arrive as VERSION and
# CONFIGUREDOCKER. Idempotent: a second run rewrites the files it owns and moves all four packages to
# the version it was asked for.
set -euo pipefail

# Unset means the default; an empty value is invalid like any other value that is not latest or X.Y.Z.
VERSION="${VERSION-latest}"
CONFIGUREDOCKER="${CONFIGUREDOCKER:-true}"

readonly KEY_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
readonly NVIDIA_FINGERPRINT="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
readonly REPO_BASE="https://nvidia.github.io/libnvidia-container/stable"
readonly REPO_ID="nvidia-container-toolkit"
readonly APT_KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
readonly RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit"
readonly DAEMON_JSON="/etc/docker/daemon.json"
readonly PACKAGES=(
  nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
)

export DEBIAN_FRONTEND=noninteractive

fail() {
  echo "(!) nvidia-container-toolkit: $*" >&2
  exit 1
}

log() {
  echo "nvidia-container-toolkit: $*"
}

# --- Validation. Nothing changes the image until the version, distribution, and architecture pass.

# [[ =~ ]] matches the whole value, so a value holding a newline cannot pass.
if [[ "$VERSION" != "latest" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid version $(printf '%q' "$VERSION"): use 'latest' or an exact MAJOR.MINOR.PATCH release such as 1.19.1."
fi

[[ -r /etc/os-release ]] || fail "cannot read /etc/os-release to detect the distribution."
# Read in subshells: /etc/os-release sets VERSION, which must not replace the option.
# shellcheck source=/dev/null
OS_ID="$(. /etc/os-release && echo "${ID:-}")"
# shellcheck source=/dev/null
OS_ID_LIKE="$(. /etc/os-release && echo "${ID_LIKE:-}")"

FAMILY=""
read -ra os_words <<<"$OS_ID $OS_ID_LIKE"
for word in "${os_words[@]}"; do
  case "$word" in
    debian | ubuntu) FAMILY="apt" ;;
    fedora | rhel) FAMILY="dnf" ;;
    opensuse | opensuse-* | suse | sles) FAMILY="zypper" ;;
    *) continue ;;
  esac
  break
done
case "$FAMILY" in
  apt) command -v apt-get >/dev/null 2>&1 || FAMILY="" ;;
  dnf) command -v dnf >/dev/null 2>&1 || FAMILY="" ;;
  zypper) command -v zypper >/dev/null 2>&1 || FAMILY="" ;;
esac
if [[ -z "$FAMILY" ]]; then
  fail "unsupported distribution '${OS_ID:-unknown}' (ID_LIKE '${OS_ID_LIKE}'): the feature needs a Debian- or" \
    "Ubuntu-based image with apt, a Fedora- or RHEL-based image with dnf, or an openSUSE- or SLES-based image with" \
    "zypper."
fi

if [[ "$FAMILY" == "apt" ]]; then
  ARCH="$(dpkg --print-architecture)" || fail "cannot detect the architecture with dpkg --print-architecture."
else
  ARCH="$(uname -m)"
fi
case "$FAMILY:$ARCH" in
  apt:amd64 | apt:arm64 | dnf:x86_64 | dnf:aarch64 | zypper:x86_64 | zypper:aarch64) ;;
  *) fail "unsupported architecture '$ARCH' on '$OS_ID': the feature supports amd64 (x86_64) and arm64 (aarch64)." ;;
esac

log "installing version '$VERSION' on '$OS_ID' ($ARCH) with $FAMILY."

# --- Prerequisites, from the image's own repositories and only when missing.

GPG=""
find_gpg() {
  GPG="$(command -v gpg || command -v gpg2 || true)"
}

install_prerequisites() {
  local missing=()
  find_gpg
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  case "$FAMILY" in
    apt)
      dpkg -s ca-certificates >/dev/null 2>&1 || missing+=(ca-certificates)
      [[ -n "$GPG" ]] || missing+=(gnupg)
      ;;
    dnf)
      rpm -q ca-certificates >/dev/null 2>&1 || missing+=(ca-certificates)
      [[ -n "$GPG" ]] || missing+=(gnupg2)
      ;;
    zypper)
      rpm -q ca-certificates >/dev/null 2>&1 || missing+=(ca-certificates)
      [[ -n "$GPG" ]] || missing+=(gpg2)
      ;;
  esac
  if ((${#missing[@]} == 0)); then
    return
  fi
  log "installing prerequisites: ${missing[*]}."
  case "$FAMILY" in
    apt)
      apt-get update
      apt-get install -y --no-install-recommends "${missing[@]}"
      ;;
    dnf) dnf install -y "${missing[@]}" ;;
    zypper) zypper --non-interactive install --no-recommends "${missing[@]}" ;;
  esac
  find_gpg
  [[ -n "$GPG" ]] || fail "gpg is still missing after installing the prerequisites."
}

# --- Signing key: exactly one primary key with the pinned fingerprint, checked in a temporary GNUPGHOME.

GNUPG_TMP=""
cleanup() {
  if [[ -n "$GNUPG_TMP" && -d "$GNUPG_TMP" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      GNUPGHOME="$GNUPG_TMP" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm -rf "$GNUPG_TMP"
  fi
}
trap cleanup EXIT

# Writes the verified key: binary for apt's signed-by keyring, armored for rpm.
install_key() {
  local key_file records primaries fingerprint exported
  GNUPG_TMP="$(mktemp -d /tmp/nvidia-container-toolkit-gnupg.XXXXXXXXXX)"
  export GNUPGHOME="$GNUPG_TMP"
  key_file="$GNUPG_TMP/gpgkey"
  exported="$GNUPG_TMP/exported"

  curl --proto '=https' -fsSL "$KEY_URL" -o "$key_file" \
    || fail "could not download NVIDIA's signing key from $KEY_URL (expected fingerprint $NVIDIA_FINGERPRINT)."
  records="$("$GPG" --batch --show-keys --with-colons "$key_file" 2>/dev/null)" \
    || fail "the file at $KEY_URL holds no readable OpenPGP key (expected fingerprint $NVIDIA_FINGERPRINT)."
  primaries="$(grep -c '^pub:' <<<"$records" || true)"
  # The first fpr record after the pub record is the primary key's; subkeys follow their own sub records.
  fingerprint="$(awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; exit }' <<<"$records")"
  if [[ "$primaries" != "1" || "$fingerprint" != "$NVIDIA_FINGERPRINT" ]]; then
    fail "the key at $KEY_URL is not NVIDIA's pinned signing key: expected exactly one primary key with fingerprint" \
      "$NVIDIA_FINGERPRINT, found $primaries primary key(s), the first with fingerprint '${fingerprint:-none}'."
  fi

  "$GPG" --batch --quiet --import "$key_file"
  if [[ "$FAMILY" == "apt" ]]; then
    "$GPG" --batch --export "$NVIDIA_FINGERPRINT" >"$exported"
    [[ -s "$exported" ]] || fail "exporting key $NVIDIA_FINGERPRINT produced nothing."
    mkdir -p "$(dirname "$APT_KEYRING")"
    install -m 0644 "$exported" "$APT_KEYRING"
  else
    "$GPG" --batch --armor --export "$NVIDIA_FINGERPRINT" >"$exported"
    [[ -s "$exported" ]] || fail "exporting key $NVIDIA_FINGERPRINT produced nothing."
    mkdir -p "$(dirname "$RPM_KEY")"
    install -m 0644 "$exported" "$RPM_KEY"
    rpm --import "$RPM_KEY"
  fi
  # Done with the temporary GNUPGHOME: nothing after this point reads it. The trap covers the failure paths.
  cleanup
  GNUPG_TMP=""
  unset GNUPGHOME
  log "verified NVIDIA's signing key $NVIDIA_FINGERPRINT."
}

# --- Repository: one source definition, written whole at a fixed path.

write_repository() {
  local repo_file pkg_check=""
  if [[ "$FAMILY" == "apt" ]]; then
    printf 'deb [signed-by=%s] %s/deb/%s /\n' "$APT_KEYRING" "$REPO_BASE" "$ARCH" >"$APT_SOURCE"
    return
  fi
  if [[ "$FAMILY" == "dnf" ]]; then
    repo_file="/etc/yum.repos.d/$REPO_ID.repo"
  else
    repo_file="/etc/zypp/repos.d/$REPO_ID.repo"
    # libzypp checks package signatures only for unsigned repositories unless pkg_gpgcheck is on (zypp.conf(5)).
    pkg_check=$'\npkg_gpgcheck=1'
  fi
  mkdir -p "$(dirname "$repo_file")"
  cat >"$repo_file" <<EOF
[$REPO_ID]
name=NVIDIA Container Toolkit
baseurl=$REPO_BASE/rpm/$ARCH
enabled=1
gpgcheck=1
repo_gpgcheck=1${pkg_check}
gpgkey=file://$RPM_KEY
EOF
}

# --- Packages: all four together, pinned to <version>-1 for an exact version.

install_packages() {
  local specs=("${PACKAGES[@]}") failed=""
  if [[ "$VERSION" != "latest" ]]; then
    case "$FAMILY" in
      apt | zypper) specs=("${PACKAGES[@]/%/=$VERSION-1}") ;;
      dnf) specs=("${PACKAGES[@]/%/-$VERSION-1}") ;;
    esac
  fi
  case "$FAMILY" in
    apt)
      apt-get update
      apt-get install -y --no-install-recommends --allow-downgrades "${specs[@]}" || failed=1
      ;;
    dnf)
      dnf install -y "${specs[@]}" || failed=1
      ;;
    zypper)
      zypper --non-interactive refresh "$REPO_ID"
      zypper --non-interactive install --no-recommends --oldpackage "${specs[@]}" || failed=1
      ;;
  esac
  if [[ -n "$failed" ]]; then
    fail "could not install NVIDIA Container Toolkit version '$VERSION' from NVIDIA's stable repository; check that" \
      "the repository offers this version for $ARCH."
  fi
}

installed_version() {
  if [[ "$FAMILY" == "apt" ]]; then
    # shellcheck disable=SC2016 # ${Version} is a dpkg-query field, not a shell variable
    dpkg-query -W -f='${Version}' "$1"
  else
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"
  fi
}

# zypper skips a downgrade silently without --oldpackage, so the result is checked, not assumed.
verify_versions() {
  local expected="" first="" package version
  if [[ "$VERSION" != "latest" ]]; then
    expected="$VERSION-1"
  fi
  for package in "${PACKAGES[@]}"; do
    version="$(installed_version "$package" 2>/dev/null)" \
      || fail "$package is not installed after installing NVIDIA Container Toolkit version '$VERSION'."
    if [[ -z "$first" ]]; then
      first="$version"
    fi
    if [[ "$version" != "$first" || (-n "$expected" && "$version" != "$expected") ]]; then
      fail "requested NVIDIA Container Toolkit version '$VERSION', but $package is at $version" \
        "(${PACKAGES[0]} at $first)."
    fi
  done
  log "installed ${PACKAGES[*]} at $first."
}

# --- Docker: register the nvidia runtime only where a Docker daemon is installed.

configure_docker() {
  if [[ "$CONFIGUREDOCKER" != "true" ]]; then
    log "configureDocker is disabled: $DAEMON_JSON is left unchanged."
    return
  fi
  # sbin directories too: distribution packages install dockerd there, and a build PATH may omit them.
  if ! PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin" command -v dockerd >/dev/null 2>&1; then
    log "no Docker daemon (dockerd) is installed: skipped the Docker configuration."
    return
  fi
  # nvidia-ctk fails on a zero-length file; treat it as an empty object.
  if [[ -f "$DAEMON_JSON" && ! -s "$DAEMON_JSON" ]]; then
    printf '{}\n' >"$DAEMON_JSON"
  fi
  # nvidia-ctk keys the runtime by name, keeps every other setting, and leaves an invalid file unwritten.
  nvidia-ctk runtime configure --runtime=docker \
    || fail "could not register the nvidia runtime in $DAEMON_JSON; check that the file holds valid JSON."
  log "registered the nvidia runtime in $DAEMON_JSON."
}

clean_caches() {
  case "$FAMILY" in
    apt)
      apt-get clean
      rm -rf /var/lib/apt/lists/*
      ;;
    dnf) dnf clean all ;;
    zypper) zypper --non-interactive clean --all ;;
  esac
}

install_prerequisites
install_key
write_repository
install_packages
verify_versions
configure_docker
clean_caches
log "done."
