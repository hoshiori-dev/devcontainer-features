#!/bin/sh
# Installs the firewall feature. Runs as root at image build time; options arrive as upper-cased env
# vars (DEFAULTACTION, PRESETS, ALLOWEDDOMAINS, ALLOWEDCIDRS, DENIEDDOMAINS, DENIEDCIDRS, FAILUREMODE,
# FILTERFORWARD). It validates every option before changing the image, installs the missing packages
# from the image's configured repositories only, and overwrites the options file and the start-time
# scripts under /usr/local/share/firewall/; the rules themselves are applied at every container start
# by apply.sh (the entrypoint) and checked by check.sh (the postStartCommand). A second run installs
# nothing new and overwrites the same files, so the later options are the only ones in effect.
# POSIX sh: Alpine ships no bash.
# shellcheck disable=SC2034 # the OPT_* values are read by the functions of scripts/common.sh
set -eu

SHARE=/usr/local/share/firewall

die() {
  printf 'firewall: %s\n' "$*" >&2
  exit 1
}

cd "$(dirname "$0")"
# shellcheck source=/dev/null
. ./scripts/common.sh

# An empty string is a value (presets "" selects none), so only an unset variable takes the default.
OPT_DEFAULT_ACTION=${DEFAULTACTION-deny}
OPT_PRESETS=${PRESETS-github}
OPT_ALLOWED_DOMAINS=${ALLOWEDDOMAINS-}
OPT_ALLOWED_CIDRS=${ALLOWEDCIDRS-}
OPT_DENIED_DOMAINS=${DENIEDDOMAINS-}
OPT_DENIED_CIDRS=${DENIEDCIDRS-}
OPT_FAILURE_MODE=${FAILUREMODE-closed}
OPT_FILTER_FORWARD=${FILTERFORWARD-true}

os_field() {
  sed -n "s/^$1=//p" /etc/os-release | head -n 1 | tr -d "\"'"
}

[ -r /etc/os-release ] || die "unsupported distribution: /etc/os-release is missing"
OS_ID=$(os_field ID)
OS_LIKE=$(os_field ID_LIKE)
OS_NAME=$(os_field PRETTY_NAME)
case " $OS_ID $OS_LIKE " in
  *" debian "* | *" ubuntu "*) FAMILY=debian ;;
  *" alpine "*) FAMILY=alpine ;;
  *" fedora "*) FAMILY=fedora ;;
  *)
    die "unsupported distribution: ${OS_NAME:-${OS_ID:-unknown}} (ID=${OS_ID:-unset});" \
      "the feature supports Debian, Ubuntu, Alpine, and Fedora"
    ;;
esac

fw_validate_options || die "$FW_ERROR"

case $FAMILY in
  debian) PACKAGES="nftables dnsmasq-base curl jq ca-certificates" ;;
  alpine) PACKAGES="nftables dnsmasq-dnssec-nftset curl jq ca-certificates" ;;
  fedora) PACKAGES="nftables dnsmasq curl jq ca-certificates" ;;
esac

installed() {
  # shellcheck disable=SC2016 # ${db:Status-Status} is a dpkg-query field, not a shell expansion
  case $FAMILY in
    debian) [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ] ;;
    alpine) apk info -e "$1" >/dev/null 2>&1 ;;
    fedora) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
  esac
}

MISSING=
for package in $PACKAGES; do
  installed "$package" || MISSING="$MISSING $package"
done
if [ -n "$MISSING" ]; then
  echo "firewall: installing$MISSING"
  # shellcheck disable=SC2086 # MISSING is a list of package names
  case $FAMILY in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y --no-install-recommends $MISSING
      rm -rf /var/lib/apt/lists/*
      ;;
    alpine)
      apk add --no-cache $MISSING
      ;;
    fedora)
      dnf install -y --setopt=install_weak_deps=False $MISSING
      dnf clean all
      ;;
  esac
fi

command -v nft >/dev/null || die "nft is missing after the package install"
dnsmasq --version \
  | awk '/^Compile time options:/ { for (i = 4; i <= NF; i++) if ($i == "nftset") ok = 1 } END { exit !ok }' \
  || die "the installed dnsmasq was built without nftables set support (nftset)"
id dnsmasq >/dev/null 2>&1 || die "the dnsmasq package did not create the dnsmasq user"

mkdir -p "$SHARE"
for script in apply.sh check.sh; do
  cp -f "scripts/$script" "$SHARE/$script"
  chmod 0755 "$SHARE/$script"
done
cp -f scripts/common.sh "$SHARE/common.sh"
chmod 0644 "$SHARE/common.sh"
fw_write_options "$SHARE/options"
chown -R 0:0 "$SHARE"
chmod 0755 "$SHARE"

echo "firewall: installed; the rules apply at every container start (options in $SHARE/options)"
