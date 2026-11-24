#!/usr/bin/env bash
# Scenario fail_contract: debian:12. Runs _feature/install.sh with local stubs to verify pre-mutation option and
# platform rejections, HTTPS transport enforcement, APT and DNF GPG key fingerprint checks, fallback warning and missing
# prerequisite errors, failed fallback archive preserving existing CLI, and clean temp/cache cleanup.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly APT_SOURCE="/etc/apt/sources.list.d/google-cloud-sdk.list"
readonly DNF_REPO="/etc/yum.repos.d/google-cloud-sdk.repo"
readonly APT_KEYRING="/usr/share/keyrings/cloud.google.gpg"
readonly SDK_DIR="/usr/local/share/google-cloud-sdk"

work="$(mktemp -d)"
mkdir -p "${work}/bin" "${work}/deny" "${work}/gpg-home"
chmod 0700 "${work}/gpg-home"

cp -p "${APT_SOURCE}" "${work}/apt-source.orig"
cp -p "${APT_KEYRING}" "${work}/apt-keyring.orig"
cp -p /etc/os-release "${work}/os-release.orig"
touch "${work}/requests" "${work}/violations"

restore() {
  cp -p "${work}/apt-source.orig" "${APT_SOURCE}"
  cp -p "${work}/apt-keyring.orig" "${APT_KEYRING}"
  cp -p "${work}/os-release.orig" /etc/os-release
  rm -rf "${DNF_REPO}" /etc/pki/rpm-gpg/RPM-GPG-KEY-google-cloud-rpm-v10 "${SDK_DIR}"
  rm -rf "${work}"
}
trap restore EXIT

# Generate an untrusted OpenPGP key and a multi-key bundle (real APT key + untrusted key) for key-pinning tests.
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends gpg-agent >/dev/null
rm -rf /var/lib/apt/lists/*
gpg --batch --homedir "${work}/gpg-home" --pinentry-mode loopback --passphrase '' \
  --quick-gen-key 'Untrusted Test <untrusted@example.invalid>' ed25519 sign never >/dev/null 2>&1
gpg --batch --homedir "${work}/gpg-home" --export >"${work}/wrong-key.gpg"
gpg --batch --homedir "${work}/gpg-home" --import "${work}/apt-keyring.orig" >/dev/null 2>&1
gpg --batch --homedir "${work}/gpg-home" --export >"${work}/multi-key.gpg"
gpgconf --homedir "${work}/gpg-home" --kill gpg-agent >/dev/null 2>&1 || true

# Create a curl stub that logs requests, asserts --proto '=https' and --proto-redir '=https', and serves fixtures.
cat >"${work}/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"${GCLOUD_TEST_LOG}"
has_proto=false
has_redir=false
output=""
url="${!#}"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --proto)
      if [[ "${2:-}" == "=https" ]]; then has_proto=true; fi
      shift
      ;;
    --proto-redir)
      if [[ "${2:-}" == "=https" ]]; then has_redir=true; fi
      shift
      ;;
    --output|-o)
      output="$2"
      shift
      ;;
  esac
  shift
done
if [[ "${has_proto}" != true || "${has_redir}" != true ]]; then
  echo "missing HTTPS flags: $*" >>"${GCLOUD_TEST_VIOLATIONS}"
  exit 99
fi
if [[ "${GCLOUD_TEST_CURL_MODE:-fail}" == fail ]]; then exit 22; fi
cp "${GCLOUD_TEST_CURL_FILE}" "${output}"
STUB
chmod +x "${work}/bin/curl"

# Fail-if-called stub for package managers / curl during pre-mutation validation tests.
cat >"${work}/deny/curl" <<'STUB'
#!/usr/bin/env bash
echo "unexpected curl: $*" >>"${GCLOUD_TEST_LOG}"
exit 98
STUB
cp "${work}/deny/curl" "${work}/deny/apt-get"
chmod +x "${work}/deny/curl" "${work}/deny/apt-get"

check_rejects_invalid_options() {
  local v c
  for v in "" "v594.0.1" "594.0" "594.0.1-rc1" "main"; do
    run_install env PATH="${work}/deny:${PATH}" GCLOUD_TEST_LOG="${work}/requests" VERSION="${v}"
    failed_with "option version" || return 1
  done
  for c in "," "kubectl," ",kubectl" "kubectl,,alpha" "kubectl alpha" "kubectl;id"; do
    run_install env PATH="${work}/deny:${PATH}" GCLOUD_TEST_LOG="${work}/requests" COMPONENTS="${c}"
    failed_with "option components" || return 1
  done
  [[ ! -s "${work}/requests" ]]
}
check "invalid version and components options fail before any download or package change" check_rejects_invalid_options

check_rejects_unsupported_arch() {
  mkdir -p "${work}/arch-stub"
  printf '#!/bin/sh\necho i386\n' >"${work}/arch-stub/dpkg"
  chmod +x "${work}/arch-stub/dpkg"
  run_install env PATH="${work}/arch-stub:${work}/deny:${PATH}" GCLOUD_TEST_LOG="${work}/requests"
  failed_with "unsupported architecture" || return 1
  [[ ! -s "${work}/requests" ]]
}
check "unsupported architecture fails before any download" check_rejects_unsupported_arch

check_rejects_missing_os_release() {
  rm -f /etc/os-release
  run_install env PATH="${work}/deny:${PATH}" GCLOUD_TEST_LOG="${work}/requests"
  cp -p "${work}/os-release.orig" /etc/os-release
  failed_with "cannot read /etc/os-release" || return 1
  [[ ! -s "${work}/requests" ]]
}
check "missing /etc/os-release fails before any download" check_rejects_missing_os_release

check_apt_key_pinning() {
  local before
  before="$(sha256sum "${APT_SOURCE}")"
  printf 'tampered-marker\n' >"${APT_SOURCE}"

  run_install env PATH="${work}/bin:${PATH}" GCLOUD_TEST_LOG="${work}/requests" \
    GCLOUD_TEST_VIOLATIONS="${work}/violations" GCLOUD_TEST_CURL_MODE=fail
  failed_with "cannot download signing key" || return 1

  run_install env PATH="${work}/bin:${PATH}" GCLOUD_TEST_LOG="${work}/requests" \
    GCLOUD_TEST_VIOLATIONS="${work}/violations" GCLOUD_TEST_CURL_MODE=serve \
    GCLOUD_TEST_CURL_FILE="${work}/wrong-key.gpg"
  failed_with "does not match pinned key" || return 1

  run_install env PATH="${work}/bin:${PATH}" GCLOUD_TEST_LOG="${work}/requests" \
    GCLOUD_TEST_VIOLATIONS="${work}/violations" GCLOUD_TEST_CURL_MODE=serve \
    GCLOUD_TEST_CURL_FILE="${work}/multi-key.gpg"
  failed_with "found 2 primary key(s)" || return 1

  [[ "$(cat "${APT_SOURCE}")" == "tampered-marker" && ! -s "${work}/violations" ]] || return 1
  cp -p "${work}/apt-source.orig" "${APT_SOURCE}"
  [[ "$(sha256sum "${APT_SOURCE}")" == "${before}" ]]
}
check "APT route rejects unreachable, wrong, and multi-key downloads over HTTPS-only curl without touching sources" \
  check_apt_key_pinning

check_dnf_key_pinning() {
  mkdir -p "${work}/dnf-stub"
  printf '#!/bin/sh\nexit 0\n' >"${work}/dnf-stub/dnf"
  printf '#!/bin/sh\nexit 0\n' >"${work}/dnf-stub/rpm"
  chmod +x "${work}/dnf-stub/dnf" "${work}/dnf-stub/rpm"
  printf 'ID=fedora\nVERSION_ID=44\n' >/etc/os-release
  run_install env PATH="${work}/bin:${work}/dnf-stub:${PATH}" GCLOUD_TEST_LOG="${work}/requests" \
    GCLOUD_TEST_VIOLATIONS="${work}/violations" GCLOUD_TEST_CURL_MODE=serve \
    GCLOUD_TEST_CURL_FILE="${work}/wrong-key.gpg"
  cp -p "${work}/os-release.orig" /etc/os-release
  failed_with "does not match pinned key" || return 1
  [[ ! -e "${DNF_REPO}" && ! -s "${work}/violations" ]]
}
check "DNF route rejects untrusted GPG key before writing repo config" check_dnf_key_pinning

check_fallback_warning_and_preserve() {
  local no_tar_dir
  no_tar_dir="${work}/no-tar"
  mkdir -p "${no_tar_dir}"
  ln -s "$(command -v curl)" "${no_tar_dir}/curl"
  ln -s "$(command -v gzip)" "${no_tar_dir}/gzip"
  ln -s "$(command -v mountpoint)" "${no_tar_dir}/mountpoint"
  ln -s "$(command -v find)" "${no_tar_dir}/find"
  ln -s "$(command -v getent)" "${no_tar_dir}/getent"
  ln -s "$(command -v stat)" "${no_tar_dir}/stat"
  ln -s "$(command -v uname)" "${no_tar_dir}/uname"
  ln -s "$(command -v id)" "${no_tar_dir}/id"
  ln -s "$(command -v bash)" "${no_tar_dir}/bash"
  ln -s "$(command -v env)" "${no_tar_dir}/env"
  ln -s "$(command -v cut)" "${no_tar_dir}/cut"
  ln -s "$(command -v readlink)" "${no_tar_dir}/readlink"
  ln -s "$(command -v printf)" "${no_tar_dir}/printf" 2>/dev/null || true

  printf 'ID=customlinux\n' >/etc/os-release
  run_install env PATH="${no_tar_dir}" GCLOUD_TEST_LOG="${work}/requests"
  output_contains 'warning: distribution "customlinux"' || {
    cp -p "${work}/os-release.orig" /etc/os-release
    return 1
  }
  failed_with "missing required tools: tar" || {
    cp -p "${work}/os-release.orig" /etc/os-release
    return 1
  }

  # Stage an existing fallback SDK, then fail archive download and confirm the existing SDK stays intact.
  mkdir -p "${SDK_DIR}/bin"
  printf '#!/bin/sh\necho "Google Cloud SDK 593.0.0"\n' >"${SDK_DIR}/bin/gcloud"
  chmod +x "${SDK_DIR}/bin/gcloud"
  run_install env PATH="${work}/bin:${PATH}" GCLOUD_TEST_LOG="${work}/requests" \
    GCLOUD_TEST_VIOLATIONS="${work}/violations" GCLOUD_TEST_CURL_MODE=fail
  cp -p "${work}/os-release.orig" /etc/os-release
  output_contains 'warning: distribution "customlinux"' || return 1
  failed_with "cannot download Google Cloud CLI archive" || return 1
  [[ "$("${SDK_DIR}/bin/gcloud" version)" == "Google Cloud SDK 593.0.0" ]]
}
check "fallback route emits warning, fails on missing tools, and preserves prior SDK on failed download" \
  check_fallback_warning_and_preserve

no_temp_residue() {
  ! compgen -G '/tmp/gcloud-cli-gnupg.*' >/dev/null \
    && ! compgen -G '/tmp/gcloud-cli-build.*' >/dev/null \
    && ! compgen -G '/usr/local/share/.gcloud-cli-install.*' >/dev/null
}

check "no temporary GnuPG or staging directories remain after failures" no_temp_residue

reportResults
