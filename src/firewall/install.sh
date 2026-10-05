#!/bin/sh
# Installs nftables, a dnsmasq built with nftables set support, curl, jq, and ca-certificates from the package
# repositories the image already configures, and writes the firewall's start-time scripts (apply.sh, check.sh,
# common.sh) and the validated options to /usr/local/share/firewall. The rules themselves are applied at every
# container start by apply.sh, the feature's entrypoint, and checked by check.sh, its postStartCommand. Runs as root
# at image build time; the options arrive as DEFAULTACTION (defaultAction), PRESETS (presets), ALLOWEDDOMAINS
# (allowedDomains), ALLOWEDCIDRS (allowedCidrs), DENIEDDOMAINS (deniedDomains), DENIEDCIDRS (deniedCidrs),
# FAILUREMODE (failureMode), and FILTERFORWARD (filterForward).
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly SHARE_DIR="/usr/local/share/firewall"
readonly OPTIONS_FILE="${SHARE_DIR}/options"
readonly APT_LISTS_DIR="/var/lib/apt/lists"

DEFAULTACTION="${DEFAULTACTION-deny}"
PRESETS="${PRESETS-github}"
ALLOWEDDOMAINS="${ALLOWEDDOMAINS-}"
ALLOWEDCIDRS="${ALLOWEDCIDRS-}"
DENIEDDOMAINS="${DENIEDDOMAINS-}"
DENIEDCIDRS="${DENIEDCIDRS-}"
FAILUREMODE="${FAILUREMODE-closed}"
FILTERFORWARD="${FILTERFORWARD-true}"

# The directory the dev container tooling unpacked the feature into; its scripts/ holds the files installed below.
source_dir="$(dirname "$0")"
# The distribution family of the image: debian, alpine, or fedora.
family=""
# Why validate_options of scripts/common.sh rejected an option value.
reason=""

# The feature's library: the option rules this script shares with apply.sh. Its path depends on where the feature
# was unpacked, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "${source_dir}/scripts/common.sh"

log() {
  printf 'firewall: %s\n' "$*"
}

fail() {
  printf 'firewall: error: %s\n' "$*" >&2
  exit 1
}

# Sets family from /etc/os-release, and fails on a distribution of no supported family.
detect_family() {
  detect_family_fix="use an image of the Debian, Ubuntu, Alpine, or Fedora family"
  [ -r /etc/os-release ] \
    || fail "cannot read /etc/os-release, so the distribution cannot be identified; ${detect_family_fix}"
  # shellcheck source=/dev/null
  detect_family_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  # shellcheck source=/dev/null
  detect_family_like="$(. /etc/os-release && printf '%s\n' "${ID_LIKE:-}")"
  case " ${detect_family_id} ${detect_family_like} " in
    *" debian "* | *" ubuntu "*) family=debian ;;
    *" alpine "*) family=alpine ;;
    *" fedora "*) family=fedora ;;
    *)
      fail "unsupported distribution \"${detect_family_id}\" (ID_LIKE \"${detect_family_like}\");" \
        "${detect_family_fix}"
      ;;
  esac
}

# Installs the packages the image lacks, with the family's package manager, from the repositories the image already
# configures; adds no repository and no key. The missing packages are this function's positional parameters.
install_packages() {
  case "${family}" in
    debian) install_packages_wanted="nftables dnsmasq-base curl jq ca-certificates" ;;
    alpine) install_packages_wanted="nftables dnsmasq-dnssec-nftset curl jq ca-certificates" ;;
    fedora) install_packages_wanted="nftables dnsmasq curl jq ca-certificates" ;;
  esac
  set --
  for install_packages_package in ${install_packages_wanted}; do
    install_packages_present=false
    case "${family}" in
      debian)
        # Known failure mode: dpkg-query exits 1 for a package dpkg has no record of, which means not installed.
        if install_packages_status="$(
          dpkg-query --show --showformat '${db:Status-Status}' "${install_packages_package}" 2>/dev/null
        )" && [ "${install_packages_status}" = "installed" ]; then
          install_packages_present=true
        fi
        ;;
      alpine)
        if apk info --installed "${install_packages_package}" >/dev/null 2>&1; then install_packages_present=true; fi
        ;;
      fedora)
        if rpm --query --whatprovides "${install_packages_package}" >/dev/null 2>&1; then
          install_packages_present=true
        fi
        ;;
    esac
    if [ "${install_packages_present}" = "false" ]; then set -- "$@" "${install_packages_package}"; fi
  done
  if [ "$#" -eq 0 ]; then return 0; fi

  case "${family}" in
    debian) install_packages_manager=apt-get ;;
    alpine) install_packages_manager=apk ;;
    fedora) install_packages_manager=dnf ;;
  esac
  command -v "${install_packages_manager}" >/dev/null 2>&1 \
    || fail "the image lacks $* and has no ${install_packages_manager} to install them with;" \
      "use an image with its package manager, or one that already holds these packages"
  log "installing $* with ${install_packages_manager} from the image's configured repositories"
  install_packages_fix="check the image's package repositories and the network access of the build"
  case "${family}" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update || fail "apt-get update failed; ${install_packages_fix}"
      apt-get install --yes --no-install-recommends "$@" || fail "apt-get install failed; ${install_packages_fix}"
      rm --recursive --force "${APT_LISTS_DIR:?}"/*
      ;;
    alpine)
      apk add --no-cache "$@" || fail "apk add failed; ${install_packages_fix}"
      ;;
    fedora)
      dnf install --assumeyes --setopt=install_weak_deps=False "$@" \
        || fail "dnf install failed; ${install_packages_fix}"
      dnf clean all
      ;;
  esac
}

# Fails unless the image now holds what the start-time scripts need of the packages: nft, a dnsmasq that can add
# addresses to nftables sets, and the dnsmasq user its package creates, which the resolver runs as.
check_packages() {
  command -v nft >/dev/null 2>&1 \
    || fail "nft is missing although the nftables package is installed; use an image whose nftables package holds it"
  check_packages_fix="use an image of the Debian, Ubuntu, Alpine, or Fedora family with its own dnsmasq package"
  check_packages_version="$(dnsmasq --version)" \
    || fail "dnsmasq does not run although its package is installed; ${check_packages_fix}"
  case "${check_packages_version}" in
    *"Compile time options:"*" nftset"*) ;;
    *) fail "the installed dnsmasq is built without nftables set support (nftset); ${check_packages_fix}" ;;
  esac
  id dnsmasq >/dev/null 2>&1 \
    || fail "the image has no dnsmasq user, which the dnsmasq package should create; ${check_packages_fix}"
}

# Writes the start-time scripts and the options, owned by root and writable by root alone, replacing what an earlier
# install wrote.
install_files() {
  log "writing apply.sh, check.sh, common.sh, and the options to ${SHARE_DIR}; the rules apply at every container start"
  mkdir --parents "${SHARE_DIR}"
  cp --force "${source_dir}/scripts/apply.sh" "${source_dir}/scripts/check.sh" "${source_dir}/scripts/common.sh" \
    "${SHARE_DIR}/"
  write_options "${OPTIONS_FILE}"
  chown --recursive 0:0 "${SHARE_DIR}"
  chmod 0755 "${SHARE_DIR}" "${SHARE_DIR}/apply.sh" "${SHARE_DIR}/check.sh"
  chmod 0644 "${SHARE_DIR}/common.sh" "${OPTIONS_FILE}"
}

main() {
  detect_family
  if ! validate_options; then fail "${reason}"; fi
  readonly DEFAULTACTION PRESETS ALLOWEDDOMAINS ALLOWEDCIDRS DENIEDDOMAINS DENIEDCIDRS FAILUREMODE FILTERFORWARD
  install_packages
  check_packages
  install_files
}

main "$@"
