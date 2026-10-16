# shellcheck shell=bash
# Assertions shared by the apptainer tests. Sourced by test.sh, duplicate.sh, and the scenario scripts after
# dev-container-features-test-lib; each function returns non-zero on failure and says why on stderr, so
# `check "<label>" <function> ...` reports it.

readonly APPTAINER_PPA_URL="https://ppa.launchpadcontent.net/apptainer/ppa/ubuntu"
readonly APPTAINER_PPA_FINGERPRINT="F6B0F5193D4F3301EF491FF0AFE36534FC6218AE"
readonly APPTAINER_EPEL_FINGERPRINT_9="FF8AD1344597106ECE813B918A3872BF3228467C"
readonly APPTAINER_APT_KEYRING="/usr/share/keyrings/apptainer-ppa-keyring.gpg"
readonly APPTAINER_APT_SOURCE="/etc/apt/sources.list.d/apptainer.sources"
readonly APPTAINER_LIBEXEC_DIR="/usr/libexec/apptainer"
readonly APPTAINER_RELEASE_LATEST_URL="https://github.com/apptainer/apptainer/releases/latest"
# A small image on Docker Hub, pinned so the sandbox checks do not follow a moving tag.
readonly APPTAINER_TEST_IMAGE="docker://docker.io/library/alpine:3.22"

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

# Prints the install path the feature took on this image: ubuntu, debian, fedora, or rhel.
apptainer_family() {
  local os_id
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in
    ubuntu) echo ubuntu ;;
    debian) echo debian ;;
    fedora) echo fedora ;;
    *) echo rhel ;;
  esac
}

# Prints the installed package version as the package manager records it.
package_version() {
  case "$(apptainer_family)" in
    ubuntu | debian)
      # ${Version} is a dpkg-query field, not a shell variable.
      # shellcheck disable=SC2016
      dpkg-query -W -f='${Version}' apptainer
      ;;
    *) rpm -q --qf '%{VERSION}-%{RELEASE}' apptainer ;;
  esac
}

# Prints the version the feature's source offers now: the PPA's candidate on Ubuntu, the newest release's tag on
# Debian, the repositories' newest apptainer on Fedora and EPEL. The source may move between the build and the test;
# a release in between fails once. A query that fails returns its status with the tool's message on stderr.
source_candidate() {
  local listing
  case "$(apptainer_family)" in
    ubuntu)
      # Error-Mode=any makes apt-get update fail when a repository cannot be fetched; by default it warns and exits 0,
      # and the candidate would then be the installed version.
      as_root apt-get update -o APT::Update::Error-Mode=any >/dev/null || return
      listing="$(apt-cache policy apptainer)" || return
      awk '$1 == "Candidate:" { print $2 }' <<<"${listing}"
      ;;
    debian)
      listing="$(curl --proto '=https' --fail --silent --show-error --location --output /dev/null \
        --write-out '%{url_effective}' "${APPTAINER_RELEASE_LATEST_URL}")" || return
      listing="${listing##*/}"
      printf '%s\n' "${listing#v}"
      ;;
    *)
      listing="$(as_root dnf repoquery --quiet --qf '%{version}-%{release}\n' apptainer)" || return
      sort -V <<<"${listing}" | awk '/^[0-9]/ { newest = $0 } END { print newest }'
      ;;
  esac
}

# The MAJOR.MINOR.PATCH part of a version string such as 1.5.4-1.fc44 or 1.5.4-stable-1~noble.
release_of() {
  local version="$1"
  if [[ "${version}" =~ ^([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "${version}"
  fi
}

# apptainer --version reports the release $1 (MAJOR.MINOR.PATCH), and the package manager records the same release.
version_reports() {
  local expected output installed
  expected="$(release_of "$1")"
  output="$(apptainer --version)" || return
  installed="$(package_version)" || return
  if [[ -z "${expected}" || "${output}" != "apptainer version ${expected}"* ]]; then
    printf '%s\n' "apptainer --version says '${output}', expected release '${expected}'" >&2
    return 1
  fi
  if [[ "$(release_of "${installed}")" != "${expected}" ]]; then
    printf '%s\n' "the package manager records ${installed}, expected release ${expected}" >&2
    return 1
  fi
}

# The source definition is the one the feature writes for this image: the PPA over HTTPS with the feature's keyring on
# Ubuntu, EPEL with package signature checking on a RHEL derivative, and no added source on Debian and Fedora.
source_is_expected() {
  local codename expected actual
  case "$(apptainer_family)" in
    ubuntu)
      # shellcheck source=/dev/null
      codename="$(. /etc/os-release && printf '%s\n' "${VERSION_CODENAME:-}")"
      expected="$(
        cat <<EOF
Types: deb
URIs: ${APPTAINER_PPA_URL}
Suites: ${codename}
Components: main
Signed-By: ${APPTAINER_APT_KEYRING}
EOF
      )"
      actual="$(<"${APPTAINER_APT_SOURCE}")" || return
      if [[ "${actual}" != "${expected}" ]]; then
        printf '%s\n' "unexpected ${APPTAINER_APT_SOURCE}:" "${actual}" "expected:" "${expected}" >&2
        return 1
      fi
      ;;
    rhel)
      if ! as_root dnf repolist --enabled | awk '$1 == "epel" { found = 1 } END { exit !found }'; then
        echo "dnf repolist --enabled lists no epel repository" >&2
        return 1
      fi
      # The [epel] section's gpgcheck line, as epel-release writes it.
      if ! awk '/^\[/ { section = $0 } section == "[epel]" && $0 == "gpgcheck=1" { found = 1 } END { exit !found }' \
        /etc/yum.repos.d/epel.repo; then
        echo "/etc/yum.repos.d/epel.repo has no gpgcheck=1 in its [epel] section" >&2
        return 1
      fi
      ;;
    *) no_added_source ;;
  esac
}

# No source definition under the package managers' directories names apptainer or the PPA.
no_added_source() {
  local matches
  matches="$(grep -rl -e apptainer -e launchpadcontent /etc/apt/sources.list.d /etc/yum.repos.d 2>/dev/null || true)"
  if [[ -n "${matches}" ]]; then
    printf '%s\n' "source definitions mention apptainer:" "${matches}" >&2
    return 1
  fi
}

# Exactly one source definition names the PPA (Ubuntu) or EPEL's [epel] section (RHEL derivative): the feature
# overwrites its files instead of appending (feature-authoring.md, Idempotency).
source_defined_once() {
  local definitions=()
  case "$(apptainer_family)" in
    ubuntu)
      readarray -t definitions < <(
        grep -hF "${APPTAINER_PPA_URL}" /etc/apt/sources.list /etc/apt/sources.list.d/*.list \
          /etc/apt/sources.list.d/*.sources 2>/dev/null
      )
      ;;
    rhel) readarray -t definitions < <(grep -hx '\[epel\]' /etc/yum.repos.d/*.repo 2>/dev/null) ;;
    *) return 0 ;;
  esac
  if ((${#definitions[@]} != 1)); then
    printf '%s\n' "the source is defined ${#definitions[@]} times:" "${definitions[@]}" >&2
    return 1
  fi
}

# The key file the feature trusts holds exactly one primary key, the pinned one: the feature's keyring on Ubuntu,
# EPEL 9's key file on a RHEL derivative; nothing to check on Debian and Fedora.
key_is_pinned() {
  local file expected home records primaries fingerprint
  case "$(apptainer_family)" in
    ubuntu)
      file="${APPTAINER_APT_KEYRING}"
      expected="${APPTAINER_PPA_FINGERPRINT}"
      ;;
    rhel)
      file="/etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9"
      expected="${APPTAINER_EPEL_FINGERPRINT_9}"
      ;;
    *) return 0 ;;
  esac
  home="$(mktemp -d)"
  # An unreadable key file leaves records empty, which the comparison below reports.
  records="$(GNUPGHOME="${home}" gpg --batch --show-keys --with-colons "${file}" 2>/dev/null)"
  rm -rf "${home}"
  primaries="$(grep -cE '^(pub|sec):' <<<"${records}" || true)"
  fingerprint="$(
    awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; exit }' <<<"${records}"
  )"
  if ((primaries != 1)) || [[ "${fingerprint}" != "${expected}" ]]; then
    printf '%s\n' "${file} holds ${primaries} primary key(s), first public fingerprint '${fingerprint}'" >&2
    return 1
  fi
}

# The setuid package is absent and no file under Apptainer's library directory is setuid.
non_setuid() {
  local setuid_files
  case "$(apptainer_family)" in
    ubuntu | debian)
      if dpkg -s apptainer-suid >/dev/null 2>&1; then
        echo "apptainer-suid is installed" >&2
        return 1
      fi
      ;;
    *)
      if rpm -q apptainer-suid >/dev/null 2>&1; then
        echo "apptainer-suid is installed" >&2
        return 1
      fi
      ;;
  esac
  setuid_files="$(find "${APPTAINER_LIBEXEC_DIR}" -type f -perm -4000 2>/dev/null)"
  if [[ -n "${setuid_files}" ]]; then
    printf '%s\n' "setuid files under ${APPTAINER_LIBEXEC_DIR}:" "${setuid_files}" >&2
    return 1
  fi
}

# The package's files, its configuration included, are as the package installed them: the feature changes none.
package_files_unchanged() {
  case "$(apptainer_family)" in
    ubuntu | debian) dpkg --verify apptainer ;;
    *) rpm --verify apptainer ;;
  esac
}

# An unprivileged user creates a user namespace with a mount namespace and mounts inside it: what the feature's
# security options make possible, and what Apptainer needs.
userns_with_mount() {
  unshare --user --map-root-user --mount sh -c 'mount -t tmpfs none /mnt && echo mounted' | grep -qx mounted
}

# Builds a sandbox from the test image into $1 and runs a command in it that names the image's distribution.
sandbox_runs() {
  local sandbox="$1"
  local output
  apptainer build --sandbox "${sandbox}" "${APPTAINER_TEST_IMAGE}" >/dev/null || return
  output="$(apptainer exec "${sandbox}" cat /etc/os-release)" || return
  grep -qx 'ID=alpine' <<<"${output}"
}

# The container's own view of its metadata: root's bounding set is Docker's default one, so the container is not
# privileged and has no added capability (the bounding set is the same for every user; CapEff differs). The seccomp
# relaxation shows as the user namespace an unprivileged user can create (userns_with_mount); /proc/self/status
# reports a seccomp filter even under seccomp=unconfined on Docker 29, so it cannot tell the profiles apart.
container_metadata() {
  local bounding
  bounding="$(awk '$1 == "CapBnd:" { print $2 }' /proc/self/status)"
  # Docker's default bounding set, as a lower-case hex mask; a privileged container or one with capAdd holds more.
  if [[ "${bounding}" != 00000000a80425fb ]]; then
    printf '%s\n' "CapBnd is ${bounding}, expected Docker's default 00000000a80425fb" >&2
    return 1
  fi
}

# Guards install.sh's cleanup of its temporary directory; no spec requirement states it.
no_temporary_dir() {
  local leftovers
  # compgen fails when the pattern matches nothing.
  if leftovers="$(compgen -G '/tmp/apptainer-install.*')"; then
    printf '%s\n' "left behind: ${leftovers}" >&2
    return 1
  fi
}

# Runs the feature's installer as root with a clean environment, as the scenarios that must show a failure do; prints
# its output and returns its status.
run_installer() {
  as_root env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root \
    bash "$(dirname "${BASH_SOURCE[0]}")/_feature/install.sh" 2>&1
}
