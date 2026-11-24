#!/usr/bin/env bash
# Installs the Google Cloud CLI (gcloud, bq, gsutil, and optional components) from Google's signed APT/DNF repositories
# with HTTPS fallback to Google's official Linux archive on other glibc distributions, and prepares ~/.config/gcloud
# state links into /var/lib/gcloud-cli. Runs as root at image build time; options `version` and `components` arrive as
# VERSION and COMPONENTS.
set -euo pipefail

readonly APT_KEY_URL="https://packages.cloud.google.com/apt/doc/apt-key.gpg"
readonly APT_FINGERPRINT="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
readonly APT_REPO_URL="https://packages.cloud.google.com/apt"
readonly APT_KEYRING="/usr/share/keyrings/cloud.google.gpg"
readonly APT_SOURCE="/etc/apt/sources.list.d/google-cloud-sdk.list"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

readonly DNF_KEY_URL="https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg"
readonly DNF_FINGERPRINT="C5F744A098136F40C370E8493156C631B64936F9"
readonly DNF_REPO_BASE="https://packages.cloud.google.com/yum/repos/cloud-sdk-el10"
readonly DNF_REPO_ID="google-cloud-cli"
readonly DNF_KEY_FILE="/etc/pki/rpm-gpg/RPM-GPG-KEY-google-cloud-rpm-v10"
readonly DNF_REPO_FILE="/etc/yum.repos.d/google-cloud-sdk.repo"

readonly ARCHIVE_LATEST_BASE="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
readonly ARCHIVE_VERSIONED_BASE="https://storage.googleapis.com/cloud-sdk-release"
readonly SDK_DIR="/usr/local/share/google-cloud-sdk"
readonly BIN_DIR="/usr/local/bin"
readonly HELPER_DIR="/usr/local/share/gcloud-cli-feature"
readonly STATE_DIR="/var/lib/gcloud-cli"
readonly STATE_CONFIG_DIR="/var/lib/gcloud-cli/config"

export DEBIAN_FRONTEND=noninteractive

# Unset means the default; an explicitly empty version is invalid and rejected by validate_options.
VERSION="${VERSION-latest}"
COMPONENTS="${COMPONENTS-}"

components_list=()
os_id=""
os_id_like=""
# Installation route: apt, dnf, or fallback.
route=""
fallback_pm="none"
arch=""
pkg_arch=""
remote_user=""
remote_home=""
gnupg_home=""
work_dir=""

log() {
  printf 'gcloud-cli: %s\n' "$*"
}

fail() {
  printf 'gcloud-cli: error: %s\n' "$*" >&2
  exit 1
}

# Removes temporary GnuPG homes and staging directories on every exit, success or failure.
cleanup() {
  if [[ -n "${gnupg_home}" && -d "${gnupg_home}" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      GNUPGHOME="${gnupg_home}" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm --recursive --force "${gnupg_home}"
    gnupg_home=""
  fi
  if [[ -n "${work_dir}" && -d "${work_dir}" ]]; then
    rm --recursive --force "${work_dir}"
    work_dir=""
  fi
}

# Runs curl enforcing HTTPS across all requests and redirects.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

gpg_installed() {
  if command -v gpg >/dev/null 2>&1; then return 0; fi
  command -v gpg2 >/dev/null 2>&1
}

run_gpg() {
  if command -v gpg >/dev/null 2>&1; then
    gpg --batch "$@"
  else
    gpg2 --batch "$@"
  fi
}

apt_install() {
  apt-get install --yes --no-install-recommends "$@"
}

# Validates option formats before touching the system. VERSION is frozen once detect_platform reads /etc/os-release.
validate_options() {
  local raw_components token seen=""
  if [[ "${VERSION}" == *$'\n'* || "${VERSION}" == *$'\r'* ]] \
    || [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or an exact MAJOR.MINOR.PATCH release such as 590.0.0"
  fi
  if [[ -n "${COMPONENTS}" ]]; then
    if [[ "${COMPONENTS}" == *$'\n'* || "${COMPONENTS}" == *$'\r'* ]]; then
      fail "option components \"${COMPONENTS}\" contains invalid whitespace; pass comma-separated component IDs"
    fi
    if [[ "${COMPONENTS}" == ,* || "${COMPONENTS}" == *, || "${COMPONENTS}" == *,,* ]]; then
      fail "option components \"${COMPONENTS}\" contains empty entries; pass comma-separated component IDs"
    fi
    IFS=',' read -ra raw_components <<<"${COMPONENTS}"
    for token in "${raw_components[@]}"; do
      if [[ ! "${token}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        fail "option components entry \"${token}\" is invalid; use lowercase letters, digits, and hyphens"
      fi
      if [[ ":${seen}:" != *":${token}:"* ]]; then
        components_list+=("${token}")
        seen="${seen:+${seen}:}${token}"
      fi
    done
  fi
  readonly COMPONENTS
}

# Detects OS family, architecture, and installation route before making any image changes.
detect_platform() {
  local distributions distribution missing=() tool ca_bundle has_ca=false
  [[ "$(uname --kernel-name)" == Linux ]] \
    || fail "unsupported operating system \"$(uname --kernel-name)\"; gcloud-cli supports Linux only"
  [[ -r /etc/os-release ]] \
    || fail "cannot read /etc/os-release to detect the distribution; use a supported Linux image with bash"

  # Read in subshells: /etc/os-release also assigns VERSION, which must not overwrite the option.
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  os_id_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"

  read -ra distributions <<<"${os_id} ${os_id_like}"
  for distribution in "${distributions[@]}"; do
    case "${distribution}" in
      debian | ubuntu)
        if command -v apt-get >/dev/null 2>&1; then route="apt"; fi
        break
        ;;
      fedora | rhel)
        if command -v dnf >/dev/null 2>&1; then route="dnf"; fi
        break
        ;;
    esac
  done

  if [[ "${route}" == apt ]]; then
    arch="$(dpkg --print-architecture)" \
      || fail "cannot detect architecture with dpkg --print-architecture; use an image with a working dpkg"
  else
    arch="$(uname --machine)"
  fi
  case "${route}:${arch}" in
    apt:amd64 | :x86_64 | dnf:x86_64) pkg_arch="x86_64" ;;
    apt:arm64 | :aarch64 | dnf:aarch64) pkg_arch="arm" ;;
    *)
      fail "unsupported architecture \"${arch}\" on \"${os_id:-unknown}\"; use an amd64 (x86_64) or arm64 (aarch64)" \
        "image"
      ;;
  esac

  if [[ -z "${route}" ]]; then
    route="fallback"
    log "warning: distribution \"${os_id:-unknown}\" is outside supported APT and DNF repositories; falling back to" \
      "official Linux archive"
    if command -v zypper >/dev/null 2>&1; then
      fallback_pm="zypper"
    elif command -v pacman >/dev/null 2>&1; then
      fallback_pm="pacman"
    else
      for tool in curl tar gzip mountpoint find getent stat; do
        if ! command -v "${tool}" >/dev/null 2>&1; then missing+=("${tool}"); fi
      done
      for ca_bundle in \
        /etc/ssl/certs/ca-certificates.crt \
        /etc/pki/tls/certs/ca-bundle.crt \
        /etc/ssl/ca-bundle.pem \
        /etc/ssl/cert.pem \
        /var/lib/ca-certificates/ca-bundle.pem; do
        if [[ -r "${ca_bundle}" ]]; then
          has_ca=true
          break
        fi
      done
      if [[ "${has_ca}" != true ]]; then missing+=(ca-certificates); fi
      if ((${#missing[@]} > 0)); then
        fail "unsupported fallback image \"${os_id:-unknown}\" without zypper or pacman is missing required tools:" \
          "${missing[*]}"
      fi
    fi
  fi
}

# Validates remote-user home and target state paths before downloading or modifying packages.
validate_state_paths() {
  local config_dir link_path
  remote_user="${_REMOTE_USER:-root}"
  remote_home="${_REMOTE_USER_HOME:-$(getent passwd "${remote_user}" | cut --delimiter=: --fields=6 || true)}"
  [[ "${remote_home}" == /* && -d "${remote_home}" ]] || fail "remote-user home is unavailable; configure remoteUser"
  [[ ! -L "${STATE_DIR}" ]] || fail "${STATE_DIR} is a symlink; restore a real mount-point directory"
  [[ ! -e "${STATE_DIR}" || -d "${STATE_DIR}" ]] \
    || fail "${STATE_DIR} is not a directory; preserve it and resolve the mount path"
  [[ ! -L "${STATE_CONFIG_DIR}" ]] || fail "${STATE_CONFIG_DIR} is a symlink; restore a real directory"
  [[ ! -e "${STATE_CONFIG_DIR}" || -d "${STATE_CONFIG_DIR}" ]] \
    || fail "${STATE_CONFIG_DIR} is not a directory; preserve it and resolve the state path"

  config_dir="${remote_home}/.config"
  link_path="${config_dir}/gcloud"
  if [[ -e "${config_dir}" && ! -d "${config_dir}" ]]; then
    fail "existing ${config_dir} is not a directory; preserve it and resolve the mapping manually"
  fi
  if [[ -L "${link_path}" ]]; then
    [[ "$(readlink --canonicalize-missing "${link_path}")" == "${STATE_CONFIG_DIR}" ]] \
      || fail "existing ${link_path} link points elsewhere; preserve it and resolve the mapping manually"
  elif [[ -e "${link_path}" ]]; then
    fail "existing ${link_path} conflicts; preserve it and migrate it explicitly before enabling this feature"
  fi
}

# Installs only missing download, verification, and initialization prerequisites from the image's own repositories.
install_prerequisites() {
  local missing=()
  if ! command -v curl >/dev/null 2>&1; then missing+=(curl); fi
  if ! command -v mountpoint >/dev/null 2>&1; then missing+=(util-linux); fi
  if ! command -v find >/dev/null 2>&1; then missing+=(findutils); fi

  case "${route}" in
    apt)
      if [[ "$(
        dpkg-query --show --showformat='${db:Status-Status}' ca-certificates 2>/dev/null || true
      )" != installed ]]; then
        missing+=(ca-certificates)
      fi
      if ! gpg_installed; then missing+=(gnupg); fi
      if ((${#missing[@]} == 0)); then return; fi
      log "installing prerequisites ${missing[*]} from the image's APT repositories"
      apt-get update \
        || fail "cannot refresh APT package lists; check the network and apt-get messages above"
      apt_install "${missing[@]}" \
        || fail "cannot install prerequisites ${missing[*]}; check the network and apt-get messages above"
      ;;
    dnf)
      if ! rpm --query ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
      if ! gpg_installed; then missing+=(gnupg2); fi
      if ((${#missing[@]} == 0)); then return; fi
      log "installing prerequisites ${missing[*]} from the image's DNF repositories"
      dnf --assumeyes install "${missing[@]}" \
        || fail "cannot install prerequisites ${missing[*]}; check the network and dnf messages above"
      ;;
    fallback)
      if ! command -v tar >/dev/null 2>&1; then missing+=(tar); fi
      if ! command -v gzip >/dev/null 2>&1; then missing+=(gzip); fi
      case "${fallback_pm}" in
        zypper)
          if ! rpm --query ca-certificates-mozilla >/dev/null 2>&1 \
            && ! rpm --query ca-certificates >/dev/null 2>&1; then
            missing+=(ca-certificates-mozilla)
          fi
          if ((${#missing[@]} == 0)); then return; fi
          log "installing prerequisites ${missing[*]} with zypper"
          zypper --non-interactive install --no-recommends "${missing[@]}" \
            || fail "cannot install prerequisites ${missing[*]}; check the network and zypper messages above"
          ;;
        pacman)
          if ! pacman -Qi ca-certificates >/dev/null 2>&1; then missing+=(ca-certificates); fi
          if ((${#missing[@]} == 0)); then return; fi
          log "installing prerequisites ${missing[*]} with pacman"
          pacman -Syu --needed --noconfirm "${missing[@]}" \
            || fail "cannot install prerequisites ${missing[*]}; check the network and pacman messages above"
          ;;
        none)
          return
          ;;
      esac
      ;;
  esac
}

# Downloads signing key $1, verifies it holds one primary public key matching fingerprint $2, and writes it to $3
# (binary keyring for apt, armored key imported into RPM for dnf).
verify_and_install_key() {
  local key_url="$1"
  local expected_fpr="$2"
  local target_path="$3"
  local key_file exported records primaries first kind fingerprint

  gnupg_home="$(mktemp --directory /tmp/gcloud-cli-gnupg.XXXXXXXXXX)"
  export GNUPGHOME="${gnupg_home}"
  key_file="${gnupg_home}/key.gpg"
  exported="${gnupg_home}/exported"

  log "downloading Google Cloud signing key from ${key_url}"
  fetch --output "${key_file}" "${key_url}" \
    || fail "cannot download signing key from ${key_url} (expected fingerprint ${expected_fpr}); check network access"
  records="$(run_gpg --show-keys --with-colons "${key_file}" 2>/dev/null)" \
    || fail "the file at ${key_url} holds no readable OpenPGP key (expected fingerprint ${expected_fpr})"

  primaries="$(grep --count --extended-regexp '^(pub|sec):' <<<"${records}" || true)"
  # mawk in base images uses short -F; capture the primary key type and first fpr record.
  first="$(
    awk -F: '$1 == "pub" || $1 == "sec" { kind = $1; next } kind && $1 == "fpr" { print kind, $10; exit }' \
      <<<"${records}"
  )"
  kind="${first%% *}"
  fingerprint="${first#* }"
  if ((primaries != 1)) || [[ "${kind}" != pub || "${fingerprint}" != "${expected_fpr}" ]]; then
    fail "signing key at ${key_url} does not match pinned key: expected 1 public primary key with fingerprint" \
      "${expected_fpr}, found ${primaries} primary key(s) (${kind:-none}: ${fingerprint:-none})"
  fi
  log "verified Google Cloud signing key ${expected_fpr}"

  run_gpg --quiet --import "${key_file}"
  mkdir --parents "${target_path%/*}"
  if [[ "${route}" == apt ]]; then
    run_gpg --export "${expected_fpr}" >"${exported}"
    [[ -s "${exported}" ]] || fail "exporting key ${expected_fpr} produced an empty keyring"
    install --mode 0644 "${exported}" "${target_path}"
  else
    run_gpg --armor --export "${expected_fpr}" >"${exported}"
    [[ -s "${exported}" ]] || fail "exporting key ${expected_fpr} produced an empty armored key"
    install --mode 0644 "${exported}" "${target_path}"
    rpm --import "${target_path}"
  fi

  GNUPGHOME="${gnupg_home}" gpgconf --kill all >/dev/null 2>&1 || true
  rm --recursive --force "${gnupg_home}"
  gnupg_home=""
  unset GNUPGHOME
}

# Maps component ID $1 to its APT/DNF package name, or prints nothing if already bundled in google-cloud-cli.
map_repo_package() {
  local component="$1"
  case "${component}" in
    alpha | beta | preview) ;;
    kubectl) printf '%s\n' "kubectl" ;;
    bigtable) printf '%s\n' "google-cloud-cli-bigtable-emulator" ;;
    cloud-datastore-emulator | gcd-emulator) printf '%s\n' "google-cloud-cli-datastore-emulator" ;;
    cloud-firestore-emulator) printf '%s\n' "google-cloud-cli-firestore-emulator" ;;
    cloud-spanner-emulator) printf '%s\n' "google-cloud-cli-spanner-emulator" ;;
    *) printf '%s\n' "google-cloud-cli-${component}" ;;
  esac
}

# Collects unique package names to install/move together across google-cloud-cli, components, and prior installs.
collect_repo_packages() {
  local packages=("google-cloud-cli")
  local seen="google-cloud-cli"
  local component mapped pkg prior_ver=""

  for component in "${components_list[@]}"; do
    mapped="$(map_repo_package "${component}")"
    if [[ -n "${mapped}" && ":${seen}:" != *":${mapped}:"* ]]; then
      packages+=("${mapped}")
      seen="${seen}:${mapped}"
    fi
  done

  if [[ "${route}" == apt ]]; then
    prior_ver="$(
      dpkg-query --show --showformat='${db:Status-Status}\t${Version}\n' google-cloud-cli 2>/dev/null \
        | awk '$1 == "installed" { print $2; exit }' || true
    )"
    while read -r pkg; do
      if [[ -n "${pkg}" && ":${seen}:" != *":${pkg}:"* ]]; then
        packages+=("${pkg}")
        seen="${seen}:${pkg}"
      fi
    done < <(
      dpkg-query --show --showformat='${db:Status-Status}\t${Package}\n' 'google-cloud-cli-*' 2>/dev/null \
        | awk '$1 == "installed" { print $2 }' || true
    )
    if [[ -n "${prior_ver}" && ":${seen}:" != *:kubectl:* ]]; then
      if [[ "$(
        dpkg-query --show --showformat='${db:Status-Status}\t${Version}\n' kubectl 2>/dev/null \
          | awk '$1 == "installed" { print $2; exit }' || true
      )" == "1:${prior_ver}" ]]; then
        packages+=(kubectl)
      fi
    fi
  else
    prior_ver="$(rpm --query --queryformat '%{VERSION}-%{RELEASE}' google-cloud-cli 2>/dev/null || true)"
    while read -r pkg; do
      if [[ -n "${pkg}" && ":${seen}:" != *":${pkg}:"* ]]; then
        packages+=("${pkg}")
        seen="${seen}:${pkg}"
      fi
    done < <(rpm --query --all --queryformat '%{NAME}\n' 'google-cloud-cli-*' 2>/dev/null || true)
    if [[ -n "${prior_ver}" && ":${seen}:" != *:kubectl:* ]] \
      && [[ "$(
        rpm --query --queryformat '%{VERSION}-%{RELEASE}' kubectl 2>/dev/null || true
      )" == "${prior_ver}" ]]; then
      packages+=(kubectl)
    fi
  fi

  printf '%s\n' "${packages[@]}"
}

# Installs google-cloud-cli and mapped component packages via Google's signed APT repository.
install_via_apt() {
  local packages=() specs=() pkg ver expected_ver=""
  verify_and_install_key "${APT_KEY_URL}" "${APT_FINGERPRINT}" "${APT_KEYRING}"
  log "configuring APT repository ${APT_REPO_URL} in ${APT_SOURCE}"
  printf 'deb [signed-by=%s] %s cloud-sdk main\n' "${APT_KEYRING}" "${APT_REPO_URL}" >"${APT_SOURCE}"

  while read -r pkg; do
    packages+=("${pkg}")
  done < <(collect_repo_packages)

  if [[ "${VERSION}" == latest ]]; then
    specs=("${packages[@]}")
  else
    for pkg in "${packages[@]}"; do
      if [[ "${pkg}" == kubectl ]]; then
        specs+=("${pkg}=1:${VERSION}-0")
      else
        specs+=("${pkg}=${VERSION}-0")
      fi
    done
  fi

  log "installing ${packages[*]} (${VERSION}) via APT with CLOUDSDK_SKIP_PY_COMPILATION=1"
  work_dir="$(mktemp --directory /tmp/gcloud-cli-build.XXXXXXXXXX)"
  apt-get update \
    || fail "cannot refresh package lists including ${APT_REPO_URL}; check network access"
  CLOUDSDK_CONFIG="${work_dir}/gcloud-config" CLOUDSDK_SKIP_PY_COMPILATION=1 \
    apt_install --allow-downgrades "${specs[@]}" \
    || fail "cannot install Google Cloud CLI version ${VERSION} and components (${COMPONENTS:-none}) via APT;" \
      "note that Google's APT repository retains versions from the last 365 days"
  rm --recursive --force "${work_dir}"
  work_dir=""

  if [[ "${VERSION}" != latest ]]; then
    for pkg in "${packages[@]}"; do
      expected_ver="${VERSION}-0"
      if [[ "${pkg}" == kubectl ]]; then expected_ver="1:${VERSION}-0"; fi
      ver="$(dpkg-query --show --showformat='${Version}' "${pkg}" 2>/dev/null || true)"
      [[ "${ver}" == "${expected_ver}" ]] \
        || fail "requested version ${VERSION}, but ${pkg} is at \"${ver:-missing}\""
    done
  fi
}

# Installs google-cloud-cli and mapped component packages via Google's signed EL10 DNF repository.
install_via_dnf() {
  local packages=() missing_specs=() existing_specs=()
  local pkg installed_ver="" current_base="" pkg_ver="" need_tx=false
  verify_and_install_key "${DNF_KEY_URL}" "${DNF_FINGERPRINT}" "${DNF_KEY_FILE}"

  log "configuring DNF repository ${DNF_REPO_BASE}-${arch} in ${DNF_REPO_FILE}"
  mkdir --parents "${DNF_REPO_FILE%/*}"
  cat >"${DNF_REPO_FILE}" <<EOF
[${DNF_REPO_ID}]
name=Google Cloud CLI
baseurl=${DNF_REPO_BASE}-${arch}
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://${DNF_KEY_FILE}
EOF

  while read -r pkg; do
    packages+=("${pkg}")
  done < <(collect_repo_packages)

  work_dir="$(mktemp --directory /tmp/gcloud-cli-build.XXXXXXXXXX)"
  # Keep RPM %post scriptlets from writing build-time config into /root/.config/gcloud.
  export CLOUDSDK_CONFIG="${work_dir}/gcloud-config"
  export CLOUDSDK_SKIP_PY_COMPILATION=1
  if [[ "${VERSION}" == latest ]]; then
    log "installing and updating ${packages[*]} (latest) via DNF with CLOUDSDK_SKIP_PY_COMPILATION=1"
    dnf --assumeyes install "${packages[@]}" \
      || fail "cannot install Google Cloud CLI and components (${COMPONENTS:-none}) via DNF"
    dnf --assumeyes upgrade "${packages[@]}" \
      || fail "cannot upgrade Google Cloud CLI and components via DNF"
  else
    installed_ver="$(rpm --query --queryformat '%{VERSION}' google-cloud-cli 2>/dev/null || true)"
    for pkg in "${packages[@]}"; do
      if rpm --query "${pkg}" >/dev/null 2>&1; then
        existing_specs+=("${pkg}-${VERSION}-1.el10")
        pkg_ver="$(rpm --query --queryformat '%{VERSION}-%{RELEASE}' "${pkg}" 2>/dev/null || true)"
        if [[ "${pkg_ver}" != "${VERSION}-1.el10" ]]; then need_tx=true; fi
      else
        missing_specs+=("${pkg}-${VERSION}-1.el10")
      fi
    done

    log "installing ${packages[*]} (${VERSION}) via DNF with CLOUDSDK_SKIP_PY_COMPILATION=1"
    if [[ "${need_tx}" == true && ${#existing_specs[@]} -gt 0 ]]; then
      current_base="${installed_ver}"
      if [[ -n "${current_base}" && "${current_base}" != "${VERSION}" ]] \
        && [[ "$(
          printf '%s\n%s\n' "${VERSION}" "${current_base}" | sort --version-sort | head --lines=1
        )" == "${VERSION}" ]]; then
        dnf --assumeyes downgrade "${existing_specs[@]}" \
          || fail "cannot downgrade Google Cloud CLI to version ${VERSION} via DNF"
      else
        dnf --assumeyes upgrade "${existing_specs[@]}" \
          || fail "cannot update Google Cloud CLI to version ${VERSION} via DNF"
      fi
    fi
    if ((${#missing_specs[@]} > 0)); then
      dnf --assumeyes install "${missing_specs[@]}" \
        || fail "cannot install Google Cloud CLI version ${VERSION} via DNF; verify the version is within 365 days"
    fi

    for pkg in "${packages[@]}"; do
      pkg_ver="$(rpm --query --queryformat '%{VERSION}-%{RELEASE}' "${pkg}" 2>/dev/null || true)"
      [[ "${pkg_ver}" == "${VERSION}-1.el10" ]] \
        || fail "requested version ${VERSION}, but ${pkg} is at \"${pkg_ver:-missing}\""
    done
  fi
  unset CLOUDSDK_CONFIG
  rm --recursive --force "${work_dir}"
  work_dir=""
}

# Prints the SDK version reported by gcloud binary $1 inside isolated HOME $2, or fails if unreadable.
read_gcloud_version() {
  local gcloud_bin="$1"
  local temp_home="$2"
  local output
  output="$(HOME="${temp_home}" "${gcloud_bin}" version 2>/dev/null)" || return 1
  awk '/^Google Cloud SDK / { print $4; exit }' <<<"${output}"
}

# Returns 0 when an already-installed archive CLI satisfies an explicit pinned version and all requested components.
archive_already_matches() {
  local temp_home="$1"
  local current_ver installed_ids component
  [[ -x "${SDK_DIR}/bin/gcloud" && "${VERSION}" != latest ]] || return 1
  current_ver="$(read_gcloud_version "${SDK_DIR}/bin/gcloud" "${temp_home}" || true)"
  [[ "${current_ver}" == "${VERSION}" ]] || return 1
  if ((${#components_list[@]} > 0)); then
    installed_ids="$(
      HOME="${temp_home}" "${SDK_DIR}/bin/gcloud" components list --only-local-state --format='value(id)' 2>/dev/null \
        || true
    )"
    for component in "${components_list[@]}"; do
      grep --line-regexp --fixed-strings --quiet "${component}" <<<"${installed_ids}" || return 1
    done
  fi
  return 0
}

# Refreshes /usr/local/bin symlinks to executable commands inside ${SDK_DIR}/bin.
link_archive_binaries() {
  local entry name
  for entry in "${BIN_DIR}"/*; do
    if [[ -L "${entry}" && "$(readlink "${entry}")" == "${SDK_DIR}/bin/"* ]]; then
      rm --force "${entry}"
    fi
  done
  for entry in "${SDK_DIR}/bin/"*; do
    if [[ -f "${entry}" && -x "${entry}" ]]; then
      name="${entry##*/}"
      ln --symbolic --force "${entry}" "${BIN_DIR}/${name}"
    fi
  done
}

# Installs gcloud CLI via Google's official Linux archive (dl.google.com for latest, cloud-sdk-release for pinned).
install_via_archive() {
  local archive_url staged_sdk staged_ver component_ver=""
  work_dir="$(mktemp --directory /usr/local/share/.gcloud-cli-install.XXXXXXXXXX)"
  mkdir --parents "${work_dir}/home" "${work_dir}/payload"

  if archive_already_matches "${work_dir}/home"; then
    log "Google Cloud CLI ${VERSION} and requested components are already installed at ${SDK_DIR}"
    link_archive_binaries
    return
  fi

  if [[ "${VERSION}" == latest ]]; then
    archive_url="${ARCHIVE_LATEST_BASE}/google-cloud-cli-linux-${pkg_arch}.tar.gz"
  else
    archive_url="${ARCHIVE_VERSIONED_BASE}/google-cloud-cli-${VERSION}-linux-${pkg_arch}.tar.gz"
  fi

  log "downloading official Linux archive from ${archive_url}"
  fetch --output "${work_dir}/gcloud.tar.gz" "${archive_url}" \
    || fail "cannot download Google Cloud CLI archive from ${archive_url}; check version ${VERSION} and network access"
  tar --extract --gzip --no-same-owner --file "${work_dir}/gcloud.tar.gz" --directory "${work_dir}/payload" \
    || fail "cannot extract downloaded archive from ${archive_url}"

  staged_sdk="${work_dir}/payload/google-cloud-sdk"
  [[ -x "${staged_sdk}/bin/gcloud" ]] \
    || fail "downloaded archive does not contain an executable google-cloud-sdk/bin/gcloud"
  staged_ver="$(read_gcloud_version "${staged_sdk}/bin/gcloud" "${work_dir}/home" || true)"
  [[ -n "${staged_ver}" ]] || fail "staged gcloud failed to report its version"
  if [[ "${VERSION}" != latest && "${staged_ver}" != "${VERSION}" ]]; then
    fail "requested archive version ${VERSION}, but staged binary reports \"${staged_ver}\""
  fi

  if ((${#components_list[@]} > 0)); then
    log "installing requested components (${components_list[*]}) via gcloud components install"
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 HOME="${work_dir}/home" \
      "${staged_sdk}/bin/gcloud" components install --quiet "${components_list[@]}" \
      || fail "cannot install requested components (${components_list[*]}); verify component IDs"
    if [[ "${VERSION}" != latest ]]; then
      component_ver="$(read_gcloud_version "${staged_sdk}/bin/gcloud" "${work_dir}/home" || true)"
      [[ "${component_ver}" == "${VERSION}" ]] \
        || fail "component installation changed staged version from ${VERSION} to \"${component_ver}\""
    fi
  fi

  log "installing Google Cloud CLI ${staged_ver} to ${SDK_DIR}"
  if [[ -e "${SDK_DIR}" ]]; then
    mv "${SDK_DIR}" "${work_dir}/previous-sdk"
  fi
  if ! mv "${staged_sdk}" "${SDK_DIR}"; then
    if [[ -e "${work_dir}/previous-sdk" && ! -e "${SDK_DIR}" ]]; then
      mv "${work_dir}/previous-sdk" "${SDK_DIR}" || true
    fi
    fail "cannot move staged SDK into ${SDK_DIR}"
  fi
  link_archive_binaries
}

# Installs the creation-time initializer and prepares /var/lib/gcloud-cli and ~/.config/gcloud.
prepare_runtime_state() {
  local group config_dir link_path
  group="$(id --group "${remote_user}")"
  log "installing ${HELPER_DIR}/initialize and preparing ${STATE_DIR} for ${remote_user}"
  install --directory --mode 0755 "${HELPER_DIR}"
  install --mode 0755 "$(dirname "$0")/initialize.sh" "${HELPER_DIR}/initialize"

  if [[ ! -e "${STATE_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_DIR}"
  fi
  if [[ ! -e "${STATE_CONFIG_DIR}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${STATE_CONFIG_DIR}"
  fi

  config_dir="${remote_home}/.config"
  if [[ ! -e "${config_dir}" ]]; then
    install --directory --mode 0700 --owner "${remote_user}" --group "${group}" "${config_dir}"
  fi
  link_path="${config_dir}/gcloud"
  if [[ ! -L "${link_path}" ]]; then
    ln --symbolic --no-target-directory "${STATE_CONFIG_DIR}" "${link_path}"
    chown --no-dereference "${remote_user}:${group}" "${link_path}"
  fi
}

clean_caches() {
  case "${route}" in
    apt)
      log "cleaning APT caches"
      apt-get clean
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    dnf)
      log "cleaning DNF caches"
      dnf clean all
      ;;
    fallback)
      if [[ "${fallback_pm}" == zypper ]]; then
        log "cleaning Zypper caches"
        zypper --non-interactive clean --all
      elif [[ "${fallback_pm}" == pacman ]]; then
        log "cleaning pacman caches"
        rm --recursive --force /var/cache/pacman/pkg/*
      fi
      ;;
  esac
}

main() {
  validate_options
  detect_platform
  # Only after detect_platform reads /etc/os-release inside subshells.
  readonly VERSION
  validate_state_paths
  trap cleanup EXIT
  install_prerequisites
  case "${route}" in
    apt) install_via_apt ;;
    dnf) install_via_dnf ;;
    fallback) install_via_archive ;;
  esac
  prepare_runtime_state
  clean_caches
  log "done"
}

main "$@"
