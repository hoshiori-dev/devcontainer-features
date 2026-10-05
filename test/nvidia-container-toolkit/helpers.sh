# shellcheck shell=bash
# Assertions shared by the nvidia-container-toolkit tests. Sourced by test.sh, duplicate.sh, and the
# scenario scripts after dev-container-features-test-lib; each function returns non-zero on failure and
# says why on stderr, so `check "<label>" <function> ...` reports it.

TOOLKIT_PACKAGES=(nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1)
TOOLKIT_NVIDIA_FINGERPRINT="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
TOOLKIT_REPO_BASE="https://nvidia.github.io/libnvidia-container/stable"
TOOLKIT_APT_KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
TOOLKIT_APT_SOURCE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
TOOLKIT_RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit"
TOOLKIT_DAEMON_JSON="/etc/docker/daemon.json"

# Runs a command as root: the tests run as the image's remote user, which may be a sudoer.
as_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

toolkit_family() {
  if command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
  else
    echo unknown
  fi
}

toolkit_repo_file() {
  case "$(toolkit_family)" in
    apt) echo "$TOOLKIT_APT_SOURCE" ;;
    dnf) echo "/etc/yum.repos.d/nvidia-container-toolkit.repo" ;;
    zypper) echo "/etc/zypp/repos.d/nvidia-container-toolkit.repo" ;;
  esac
}

toolkit_repo_url() {
  if [[ "$(toolkit_family)" == "apt" ]]; then
    echo "$TOOLKIT_REPO_BASE/deb/$(dpkg --print-architecture)"
  else
    echo "$TOOLKIT_REPO_BASE/rpm/$(uname -m)"
  fi
}

# Installed version-release of one package, e.g. 1.20.1-1.
package_version() {
  if [[ "$(toolkit_family)" == "apt" ]]; then
    # shellcheck disable=SC2016 # ${Version} is a dpkg-query field, not a shell variable
    dpkg-query -W -f='${Version}' "$1"
  else
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"
  fi
}

# Newest version-release of nvidia-container-toolkit that NVIDIA's repository offers, from the package
# manager itself; the install cleaned its caches, so the metadata is fetched again first.
newest_candidate() {
  case "$(toolkit_family)" in
    apt)
      as_root apt-get update >/dev/null 2>&1 || return 1
      apt-cache policy nvidia-container-toolkit | awk '$1 == "Candidate:" { print $2 }'
      ;;
    dnf)
      as_root dnf repoquery --quiet --repo nvidia-container-toolkit --qf '%{version}-%{release}\n' \
        nvidia-container-toolkit 2>/dev/null | grep -E '^[0-9]' | sort -V | tail -n 1
      ;;
    zypper)
      as_root zypper --non-interactive --quiet refresh nvidia-container-toolkit >/dev/null 2>&1 || return 1
      zypper --non-interactive info nvidia-container-toolkit | awk -F' *: *' '$1 == "Version" { print $2; exit }'
      ;;
  esac
}

# All four packages installed at the given version-release.
packages_at() {
  local expected="$1" package version
  if [[ -z "$expected" ]]; then
    echo "no expected version (the repository query returned nothing)" >&2
    return 1
  fi
  for package in "${TOOLKIT_PACKAGES[@]}"; do
    version="$(package_version "$package" 2>/dev/null)" || {
      echo "$package is not installed" >&2
      return 1
    }
    if [[ "$version" != "$expected" ]]; then
      echo "$package is at $version, expected $expected" >&2
      return 1
    fi
  done
}

# nvidia-ctk --version reports the given MAJOR.MINOR.PATCH on its first line.
ctk_reports() {
  local first_line
  first_line="$(nvidia-ctk --version | head -n 1)"
  if [[ "$first_line" != *" version $1" ]]; then
    echo "nvidia-ctk --version says '$first_line', expected version $1" >&2
    return 1
  fi
}

# The source definition the feature writes, with signature checks on and only the local key.
repository_file_is_expected() {
  local file url
  file="$(toolkit_repo_file)"
  url="$(toolkit_repo_url)"
  if [[ "$(toolkit_family)" == "apt" ]]; then
    [[ "$(cat "$file")" == "deb [signed-by=$TOOLKIT_APT_KEYRING] $url /" ]] || {
      echo "unexpected $file: $(cat "$file")" >&2
      return 1
    }
    return 0
  fi
  if ! grep -qx "baseurl=$url" "$file" \
    || ! grep -qx "gpgcheck=1" "$file" \
    || ! grep -qx "repo_gpgcheck=1" "$file" \
    || [[ "$(grep '^gpgkey=' "$file")" != "gpgkey=file://$TOOLKIT_RPM_KEY" ]] \
    || { [[ "$(toolkit_family)" == "zypper" ]] && ! grep -qx "pkg_gpgcheck=1" "$file"; }; then
    echo "unexpected $file: $(cat "$file")" >&2
    return 1
  fi
}

# The package manager lists NVIDIA's stable repository for this architecture as a source.
repository_listed() {
  local url
  url="$(toolkit_repo_url)"
  case "$(toolkit_family)" in
    apt)
      as_root apt-get update >/dev/null 2>&1 || return 1
      apt-cache policy | grep -qF "$url"
      ;;
    dnf) as_root dnf repolist --enabled 2>/dev/null | grep -q '^nvidia-container-toolkit\b' ;;
    zypper) zypper --non-interactive repos --uri | grep -F "nvidia-container-toolkit" | grep -qF "$url" ;;
  esac
}

# Exactly one source definition in the image points at NVIDIA's repository.
repository_defined_once() {
  local count
  case "$(toolkit_family)" in
    apt)
      count="$(cat /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources \
        2>/dev/null | grep -c "nvidia.github.io/libnvidia-container" || true)"
      ;;
    dnf) count="$(cat /etc/yum.repos.d/*.repo 2>/dev/null | grep -c "^baseurl=.*nvidia.github.io" || true)" ;;
    zypper) count="$(cat /etc/zypp/repos.d/*.repo 2>/dev/null | grep -c "^baseurl=.*nvidia.github.io" || true)" ;;
  esac
  if [[ "$count" != "1" ]]; then
    echo "NVIDIA's repository is defined $count times" >&2
    return 1
  fi
}

# The key file the repository uses holds exactly one primary key, NVIDIA's pinned one.
key_is_pinned() {
  local file home records primaries fingerprint
  if [[ "$(toolkit_family)" == "apt" ]]; then file="$TOOLKIT_APT_KEYRING"; else file="$TOOLKIT_RPM_KEY"; fi
  home="$(mktemp -d)"
  records="$(GNUPGHOME="$home" gpg --batch --show-keys --with-colons "$file" 2>/dev/null)"
  rm -rf "$home"
  # A secret-key block (sec record) is a primary key too; the one key must be the public key (pub record).
  primaries="$(grep -cE '^(pub|sec):' <<<"$records" || true)"
  fingerprint="$(awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; exit }' <<<"$records")"
  if [[ "$primaries" != "1" || "$fingerprint" != "$TOOLKIT_NVIDIA_FINGERPRINT" ]]; then
    echo "$file holds $primaries primary key(s), first public fingerprint '$fingerprint'" >&2
    return 1
  fi
}

no_temporary_gnupghome() {
  if compgen -G "/tmp/nvidia-container-toolkit-gnupg.*" >/dev/null; then
    echo "left behind: $(compgen -G "/tmp/nvidia-container-toolkit-gnupg.*")" >&2
    return 1
  fi
}

no_daemon_json() {
  [[ ! -e "$TOOLKIT_DAEMON_JSON" ]]
}

# daemon.json holds the nvidia runtime entry the feature registers.
daemon_json_has_nvidia() {
  jq -e '.runtimes.nvidia.path == "nvidia-container-runtime"' "$TOOLKIT_DAEMON_JSON" >/dev/null
}
