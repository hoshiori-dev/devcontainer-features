# shellcheck shell=bash
# Assertions shared by the nvidia-container-toolkit tests. Sourced by test.sh, duplicate.sh, and the scenario scripts
# after dev-container-features-test-lib; each function returns non-zero on failure and says why on stderr, so
# `check "<label>" <function> ...` reports it.

readonly TOOLKIT_PACKAGES=(
  nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
)
readonly TOOLKIT_NVIDIA_FINGERPRINT="C95B321B61E88C1809C4F759DDCAE044F796ECB0"
readonly TOOLKIT_REPO_BASE="https://nvidia.github.io/libnvidia-container/stable"
readonly TOOLKIT_APT_KEYRING="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
readonly TOOLKIT_APT_SOURCE="/etc/apt/sources.list.d/nvidia-container-toolkit.list"
readonly TOOLKIT_RPM_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-nvidia-container-toolkit"
readonly TOOLKIT_DAEMON_JSON="/etc/docker/daemon.json"

# Runs a command as root: the tests run as the image's remote user, which may be a sudoer.
as_root() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

# Prints the image's package manager family: apt, dnf, zypper, or unknown.
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

# Prints the path of the source definition the feature writes on this image.
toolkit_repo_file() {
  case "$(toolkit_family)" in
    apt) printf '%s\n' "${TOOLKIT_APT_SOURCE}" ;;
    dnf) echo "/etc/yum.repos.d/nvidia-container-toolkit.repo" ;;
    zypper) echo "/etc/zypp/repos.d/nvidia-container-toolkit.repo" ;;
  esac
}

# Prints the URL of NVIDIA's stable repository for this image's package manager and architecture.
toolkit_repo_url() {
  local arch
  if [[ "$(toolkit_family)" == apt ]]; then
    arch="$(dpkg --print-architecture)"
    printf '%s\n' "${TOOLKIT_REPO_BASE}/deb/${arch}"
  else
    arch="$(uname -m)"
    printf '%s\n' "${TOOLKIT_REPO_BASE}/rpm/${arch}"
  fi
}

# Prints the installed version-release of the package $1, such as 1.20.1-1.
package_version() {
  if [[ "$(toolkit_family)" == apt ]]; then
    # ${Version} is a dpkg-query field, not a shell variable.
    # shellcheck disable=SC2016
    dpkg-query -W -f='${Version}' "$1"
  else
    rpm -q --qf '%{VERSION}-%{RELEASE}' "$1"
  fi
}

# Prints the newest version-release of nvidia-container-toolkit that NVIDIA's repository offers, from the package
# manager itself; the install cleaned its caches, so the metadata is fetched again first. A query that fails returns
# its status and leaves the package manager's own message on stderr.
newest_candidate() {
  local listing
  case "$(toolkit_family)" in
    apt)
      # Error-Mode=any makes apt-get update fail when a repository cannot be fetched; by default it warns and exits 0,
      # and the candidate would then be the installed version.
      as_root apt-get update -o APT::Update::Error-Mode=any >/dev/null || return
      listing="$(apt-cache policy nvidia-container-toolkit)" || return
      awk '$1 == "Candidate:" { print $2 }' <<<"${listing}"
      ;;
    dnf)
      # skip_if_unavailable=false makes dnf fail when it cannot fetch NVIDIA's repository; by default it skips the
      # repository, prints nothing, and exits 0.
      listing="$(
        as_root dnf repoquery --quiet --repo nvidia-container-toolkit \
          --setopt=nvidia-container-toolkit.skip_if_unavailable=false --qf '%{version}-%{release}\n' \
          nvidia-container-toolkit
      )" || return
      sort -V <<<"${listing}" | awk '/^[0-9]/ { newest = $0 } END { print newest }'
      ;;
    zypper)
      as_root zypper --non-interactive --quiet refresh nvidia-container-toolkit >/dev/null || return
      listing="$(zypper --non-interactive info nvidia-container-toolkit)" || return
      awk -F' *: *' '$1 == "Version" { print $2; exit }' <<<"${listing}"
      ;;
  esac
}

# All four packages are installed at the version-release $1.
packages_at() {
  local expected="$1"
  local package version
  if [[ -z "${expected}" ]]; then
    echo "no expected version (the repository query returned nothing)" >&2
    return 1
  fi
  for package in "${TOOLKIT_PACKAGES[@]}"; do
    if ! version="$(package_version "${package}" 2>/dev/null)"; then
      printf '%s\n' "${package} is not installed" >&2
      return 1
    fi
    if [[ "${version}" != "${expected}" ]]; then
      printf '%s\n' "${package} is at ${version}, expected ${expected}" >&2
      return 1
    fi
  done
}

# nvidia-ctk --version reports the MAJOR.MINOR.PATCH version $1 on its first line.
ctk_reports() {
  local output first_line
  output="$(nvidia-ctk --version)" || return
  first_line="${output%%$'\n'*}"
  if [[ "${first_line}" != *" version $1" ]]; then
    printf '%s\n' "nvidia-ctk --version says '${first_line}', expected version $1" >&2
    return 1
  fi
}

# The repository configuration is, as a whole apart from trailing newlines, the one the feature writes: NVIDIA's stable
# repository for this architecture, signature-checked against the local copy of the key alone.
repository_file_is_expected() {
  local file url expected actual
  file="$(toolkit_repo_file)"
  url="$(toolkit_repo_url)"
  case "$(toolkit_family)" in
    apt) expected="deb [signed-by=${TOOLKIT_APT_KEYRING}] ${url} /" ;;
    dnf)
      expected="$(
        cat <<EOF
[nvidia-container-toolkit]
name=NVIDIA Container Toolkit
baseurl=${url}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://${TOOLKIT_RPM_KEY}
EOF
      )"
      ;;
    zypper)
      expected="$(
        cat <<EOF
[nvidia-container-toolkit]
name=NVIDIA Container Toolkit
baseurl=${url}
enabled=1
gpgcheck=1
repo_gpgcheck=1
pkg_gpgcheck=1
gpgkey=file://${TOOLKIT_RPM_KEY}
EOF
      )"
      ;;
  esac
  actual="$(<"${file}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '%s\n' "unexpected ${file}:" "${actual}" "expected:" "${expected}" >&2
    return 1
  fi
}

# Exactly one source definition in the image points at NVIDIA's repository. No spec sentence states this for one
# install; it checks the convention that a feature overwrites its files instead of appending to them
# (feature-authoring.md, Idempotency), which Requirement "Installing twice" calls one consistent installation.
repository_defined_once() {
  local definitions=()
  # A glob that matches no file stays literal and grep reports it, so grep's messages are dropped; its status does not
  # reach readarray, and no match leaves the list empty.
  case "$(toolkit_family)" in
    apt)
      readarray -t definitions < <(
        grep -hF "nvidia.github.io/libnvidia-container" \
          /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null
      )
      ;;
    dnf) readarray -t definitions < <(grep -hE '^baseurl=.*nvidia\.github\.io' /etc/yum.repos.d/*.repo 2>/dev/null) ;;
    zypper)
      readarray -t definitions < <(grep -hE '^baseurl=.*nvidia\.github\.io' /etc/zypp/repos.d/*.repo 2>/dev/null)
      ;;
  esac
  if ((${#definitions[@]} != 1)); then
    printf '%s\n' "NVIDIA's repository is defined ${#definitions[@]} times:" "${definitions[@]}" >&2
    return 1
  fi
}

# The key file the repository uses holds exactly one primary key, NVIDIA's pinned one.
key_is_pinned() {
  local file="${TOOLKIT_RPM_KEY}"
  local home records primaries fingerprint
  if [[ "$(toolkit_family)" == apt ]]; then file="${TOOLKIT_APT_KEYRING}"; fi
  home="$(mktemp -d)"
  # An unreadable key file leaves records empty, which the comparison below reports.
  records="$(GNUPGHOME="${home}" gpg --batch --show-keys --with-colons "${file}" 2>/dev/null)"
  rm -rf "${home}"
  # A secret-key block (sec record) is a primary key too; the one key must be the public key (pub record). grep exits
  # 1 when it counts no line and still prints 0, so its status is ignored.
  primaries="$(grep -cE '^(pub|sec):' <<<"${records}" || true)"
  fingerprint="$(
    awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; exit }' <<<"${records}"
  )"
  if ((primaries != 1)) || [[ "${fingerprint}" != "${TOOLKIT_NVIDIA_FINGERPRINT}" ]]; then
    printf '%s\n' "${file} holds ${primaries} primary key(s), first public fingerprint '${fingerprint}'" >&2
    return 1
  fi
}

# Guards install.sh's cleanup of the temporary GnuPG home it verifies the key in; no spec requirement states it.
no_temporary_gnupghome() {
  local leftovers
  # compgen fails when the pattern matches nothing.
  if leftovers="$(compgen -G '/tmp/nvidia-container-toolkit-gnupg.*')"; then
    printf '%s\n' "left behind: ${leftovers}" >&2
    return 1
  fi
}

no_daemon_json() {
  [[ ! -e "${TOOLKIT_DAEMON_JSON}" ]]
}

# daemon.json holds the nvidia runtime entry the feature registers.
daemon_json_has_nvidia() {
  jq -e '.runtimes.nvidia.path == "nvidia-container-runtime"' "${TOOLKIT_DAEMON_JSON}" >/dev/null
}
