#!/usr/bin/env bash
# Scenario test_keyring_and_configuration (scenarios.json): the feature is installed with an empty list, and this script
# then runs install.sh and compares the pacman configuration and the keyring before and after. Spec scenarios "Pacman
# configuration is unchanged" and "Missing certified key is fetched".
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# Prints a digest of /etc/pacman.conf and everything under /etc/pacman.d, the mirror list and the keyring included:
# names, types, modes, link targets, and the content of every file.
pacman_configuration() {
  {
    find /etc/pacman.conf /etc/pacman.d \( -type f -o -type l -o -type d \) -printf '%p %y %m %l\n' | sort
    find /etc/pacman.conf /etc/pacman.d -type f -exec sha256sum {} + | sort
  } | sha256sum
}

pacman_configuration_is() {
  if [[ "$(pacman_configuration)" != "$1" ]]; then
    echo "/etc/pacman.conf or /etc/pacman.d changed" >&2
    return 1
  fi
}

# Prints the names of the packages whose name or version is in the installed packages now and not in the listing $1.
changed_packages() {
  comm -13 <(sort <<<"$1") <(local_database | sort) | cut -d' ' -f1
}

# None of the packages given owns /etc/pacman.conf or a file under /etc/pacman.d.
own_no_pacman_configuration() {
  local owned
  owned="$(pacman -Qlq -- "$@" | grep -E '^/etc/pacman\.(conf$|d/)')" || owned=""
  if [[ -n "${owned}" ]]; then
    printf 'the changed packages own:\n%s\n' "${owned}" >&2
    return 1
  fi
}

bc_is_among() {
  local package
  for package in "$@"; do
    if [[ "${package}" == bc ]]; then return 0; fi
  done
  echo "bc is not among: $*" >&2
  return 1
}

imported_no_key() {
  if printed "Import PGP key" 2>/dev/null; then
    echo "the transaction imported a packager key, so the scenario's precondition does not hold" >&2
    return 1
  fi
}

is_fingerprint() {
  [[ "$1" =~ ^[0-9A-F]{40}$ ]]
}

# Runs gpg on the image's pacman keyring.
keyring() {
  gpg --homedir /etc/pacman.d/gnupg --batch "$@"
}

in_keyring() {
  keyring --list-keys -- "$1" >/dev/null 2>&1
}

not_in_keyring() {
  ! in_keyring "$1"
}

# Bring the container current first, so that the feature's transaction holds only bc and its dependencies.
pacman -Syu --noconfirm >/dev/null
remove_caches
configuration_before="$(pacman_configuration)"
database_before="$(local_database)"
run_install PACKAGES=bc
check "bc installs" exited_with 0
readarray -t changed < <(changed_packages "${database_before}")
echo "the transaction installed or upgraded: ${changed[*]}"
check "bc is among the packages the run installed or upgraded" bc_is_among "${changed[@]}"
check "premise: no installed or upgraded package owns /etc/pacman.conf or a file under /etc/pacman.d" \
  own_no_pacman_configuration "${changed[@]}"
check "premise: the run imported no packager key" imported_no_key
check "/etc/pacman.conf and /etc/pacman.d, the mirror list and the keyring included, are as before the run" \
  pacman_configuration_is "${configuration_before}"

# The key that signs tree, which is not installed: read from the package's detached signature.
check "premise: tree is not installed" not_installed tree
download_sync_databases
pacman -Sw --noconfirm tree >/dev/null
packets="$(keyring --list-packets /var/cache/pacman/pkg/tree-*.sig 2>/dev/null)"
signer="$(sed -n 's/.*issuer fpr v[0-9]* \([0-9A-F]*\)).*/\1/p' <<<"${packets}" | head -n 1)"
check "premise: tree's signature names its issuer's fingerprint: ${signer}" is_fingerprint "${signer}"
key="$(keyring --with-colons --list-keys -- "${signer}" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
pacman-key --delete "${key}" >/dev/null 2>&1
check "premise: the key ${key} of tree's signer is deleted from the keyring" not_in_keyring "${key}"
remove_caches
run_install PACKAGES=tree
check "tree, signed with the deleted key ${key}, installs" exited_with 0
check "pacman imports the key" printed "Import PGP key"
check "tree is installed" installed tree
check "the key ${key} is back in the keyring" in_keyring "${key}"

reportResults
