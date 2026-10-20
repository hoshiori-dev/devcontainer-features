#!/usr/bin/env bash
# Installs Quarto's verified official tarball under /opt/quarto and links /usr/local/bin/quarto.
# Runs as root at image build time; the version option arrives as VERSION.
set -euo pipefail

readonly API="https://api.github.com/repos/quarto-dev/quarto-cli/releases"
readonly RELEASES="https://github.com/quarto-dev/quarto-cli/releases/download"
readonly TARGET="/opt/quarto"
readonly COMMAND="/usr/local/bin/quarto"
readonly MARKER=".devcontainer-feature-quarto"
readonly STAGING="/opt/.quarto-feature.XXXXXX"
readonly APT_LISTS="/var/lib/apt/lists"
readonly OPT_DIR="/opt"
VERSION="${VERSION-latest}"
os_id=""
arch=""
version=""
work=""
backup=""
activated=false
committed=false
managed=false

log() { printf 'quarto: %s\n' "$*"; }
fail() { printf 'quarto: error: %s\n' "$*" >&2; exit 1; }

# Restores the previous tree on failed activation, and removes only our temporary paths.
cleanup() {
  if [[ "${activated}" == true && "${committed}" == false ]]; then
    rm --recursive --force "${TARGET}"
    if [[ -n "${backup}" ]]; then
      mv -- "${backup}" "${TARGET}"
      ln --symbolic --force "${TARGET}/bin/quarto" "${COMMAND}"
    else
      rm --force "${COMMAND}"
    fi
  elif [[ -n "${backup}" && ! -e "${TARGET}" ]]; then
    mv -- "${backup}" "${TARGET}"
  fi
  if [[ -n "${work}" ]]; then rm --recursive --force "${work}"; fi
}

# HTTPS redirects only; retries handle transient network and upstream failures.
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "invalid version '${VERSION}'; use latest or an exact stable MAJOR.MINOR.PATCH release"
  fi
}

detect_platform() {
  local machine
  [[ -r /etc/os-release ]] || fail "cannot identify distribution; use Debian, Ubuntu, or Fedora"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  case "${os_id}" in
    debian | ubuntu | fedora) ;;
    *) fail "unsupported distribution ${os_id}; use Debian, Ubuntu, or Fedora" ;;
  esac
  machine="$(uname --machine)"
  case "${machine}" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) fail "unsupported architecture ${machine}; use amd64 or arm64" ;;
  esac
  if compgen -G '/lib/ld-musl-*.so*' >/dev/null; then fail "musl is unsupported; use a glibc image"; fi
}

# Discovers foreign commands without executing their binaries.
check_conflicts() {
  local path
  local resolved
  local remote_path
  if [[ -e "${TARGET}" || -L "${TARGET}" ]]; then
    [[ -d "${TARGET}" && ! -L "${TARGET}" && -f "${TARGET}/${MARKER}" ]] \
      || fail "${TARGET} is unmanaged; remove the existing installation first"
    [[ "$(stat --format '%u:%a' "${TARGET}/${MARKER}")" == 0:644 \
      && "$(stat --format '%u' "${TARGET}")" == 0 ]] \
      || fail "${TARGET} has unmanaged ownership; remove the existing installation first"
    managed=true
  fi
  if [[ -e "${COMMAND}" || -L "${COMMAND}" ]]; then
    [[ "${managed}" == true && -L "${COMMAND}" && "$(readlink "${COMMAND}")" == "${TARGET}/bin/quarto" ]] \
      || fail "${COMMAND} is occupied; remove the existing installation first"
  fi
  remote_path="${PATH}"
  if [[ "${_REMOTE_USER:-root}" != root ]]; then
    # The login shell must expand its own PATH, not the installer's PATH.
    # shellcheck disable=SC2016
    remote_path="$(runuser --login "${_REMOTE_USER}" --command 'printf "%s" "$PATH"')" \
      || fail "cannot inspect the remote user's PATH; check the configured user"
  fi
  while IFS= read -r path; do
    path="${path:-.}"
    [[ -x "${path}/quarto" && ! -d "${path}/quarto" ]] || continue
    resolved="$(readlink --canonicalize-missing "${path}/quarto")"
    [[ "${managed}" == true && "${resolved}" == "${TARGET}/bin/quarto" ]] \
      || fail "${path}/quarto conflicts with this feature; remove the existing installation first"
  done < <(printf '%s:%s\n' "${PATH}" "${remote_path}" | tr ':' '\n')
}

install_prerequisites() {
  local packages=()
  local utility
  for utility in curl tar gzip sha256sum jq awk which; do
    if ! command -v "${utility}" >/dev/null; then
      case "${utility}" in
        sha256sum) packages+=(coreutils) ;;
        awk) packages+=(gawk) ;;
        which)
          if [[ "${os_id}" == fedora ]]; then packages+=(which); else packages+=(debianutils); fi
          ;;
        *) packages+=("${utility}") ;;
      esac
    fi
  done
  if [[ "${os_id}" == fedora ]]; then
    if ! rpm --query ca-certificates >/dev/null; then packages+=(ca-certificates); fi
    if ! rpm --query libstdc++ >/dev/null; then packages+=(libstdc++); fi
    if [[ ${#packages[@]} -gt 0 ]]; then
      log "installing prerequisites from configured Fedora repositories"
      dnf --assumeyes install "${packages[@]}" || fail "cannot install prerequisites; check configured repositories"
      dnf clean all
    fi
  else
    for utility in ca-certificates libstdc++6; do
      if ! dpkg-query --show --showformat='${Status}' "${utility}" 2>/dev/null \
        | grep --quiet 'install ok installed'; then
        packages+=("${utility}")
      fi
    done
    if [[ ${#packages[@]} -gt 0 ]]; then
      log "installing prerequisites from configured Debian/Ubuntu repositories"
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || fail "cannot update package lists; check configured repositories"
      apt-get --yes --no-install-recommends install "${packages[@]}" \
        || fail "cannot install prerequisites; check configured repositories"
      rm --recursive --force "${APT_LISTS:?}/"*
    fi
  fi
}

resolve_release() {
  local endpoint="${API}/latest"
  local tag
  if [[ "${VERSION}" != latest ]]; then endpoint="${API}/tags/v${VERSION#v}"; fi
  log "resolving stable release from ${endpoint} to ${work}/release.json"
  fetch --output "${work}/release.json" "${endpoint}" \
    || fail "cannot resolve ${VERSION}; check release availability, connectivity, and GitHub API rate limits"
  tag="$(jq --exit-status --raw-output \
    'select(.draft == false and .prerelease == false) | .tag_name | select(type == "string")' \
    "${work}/release.json")" || fail "${VERSION} has invalid or prerelease metadata; choose a stable release"
  [[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid stable tag ${tag}; choose an exact release"
  version="${tag#v}"
  [[ "${VERSION}" == latest || "${VERSION#v}" == "${version}" ]] \
    || fail "release metadata does not match ${VERSION}; check the requested release"
  jq --exit-status --arg name "quarto-${version}-linux-${arch}.tar.gz" \
    'any(.assets[]; .name == $name)' "${work}/release.json" >/dev/null \
    || fail "release ${version} has no ${arch} archive; select a compatible stable release"
}

install_release() {
  local archive="quarto-${version}-linux-${arch}.tar.gz"
  local base="${RELEASES}/v${version}"
  local digest
  local actual
  log "downloading ${base}/${archive} and its checksum list to ${work}"
  fetch --output "${work}/archive.tar.gz" "${base}/${archive}" \
    || fail "cannot download ${archive}; check release availability and connectivity"
  fetch --output "${work}/checksums.txt" "${base}/quarto-${version}-checksums.txt" \
    || fail "cannot obtain required checksums for ${version}; select a release publishing checksums"
  digest="$(awk -v name="${archive}" '$2 == name || $2 == "*" name {print $1}' "${work}/checksums.txt")"
  [[ "${digest}" =~ ^[a-fA-F0-9]{64}$ ]] \
    || fail "missing, duplicated, or invalid checksum for ${archive}; check upstream verification data"
  actual="$(sha256sum "${work}/archive.tar.gz")"
  [[ "${actual%% *}" == "${digest,,}" ]] || fail "checksum mismatch for ${archive}; retry with a clean download"
  log "extracting verified ${archive} into ${work}/new"
  mkdir "${work}/new"
  tar --extract --gzip --file "${work}/archive.tar.gz" --directory "${work}/new" --strip-components=1 \
    || fail "cannot extract ${archive}; check the release archive"
  [[ "$("${work}/new/bin/quarto" --version)" == "${version}" ]] \
    || fail "release ${version} cannot run on this image; choose a compatible release or image"
  printf '%s\n' "${version}" >"${work}/new/${MARKER}"
  chown --recursive root:root "${work}/new"
  chmod --recursive go-w "${work}/new"
  chmod 0644 "${work}/new/${MARKER}"
  if [[ "${managed}" == true ]]; then
    backup="${work}/previous"
    mv -- "${TARGET}" "${backup}"
  fi
  log "activating Quarto ${version} at ${TARGET}"
  mv -- "${work}/new" "${TARGET}"
  activated=true
  mkdir --parents "${COMMAND%/*}"
  ln --symbolic --force "${TARGET}/bin/quarto" "${COMMAND}"
  [[ "$("${COMMAND}" --version)" == "${version}" ]] \
    || fail "activated release ${version} is unusable; restoring the previous installation"
  committed=true
}

main() {
  validate_options
  detect_platform
  readonly VERSION
  check_conflicts
  install_prerequisites
  mkdir --parents "${OPT_DIR}"
  work="$(mktemp --directory "${STAGING}")"
  trap cleanup EXIT
  resolve_release
  if [[ "${managed}" == true && -L "${COMMAND}" \
    && "$(cat "${TARGET}/${MARKER}")" == "${version}" ]]; then
    if [[ "$("${TARGET}/bin/quarto" --version)" == "${version}" ]]; then
      log "release ${version} is already installed; skipping archive download"
      return
    fi
  fi
  install_release
}

main "$@"
