#!/usr/bin/env bash
# Scenario fail_refresh_0 (scenarios.json): this script runs install.sh in a container whose repositories it has
# broken, one way at a time. Spec scenarios "Failed refresh fails the feature" and "Refresh is explicitly requested"
# (an unavailable repository beside the image's own), "Unsigned repository fails the refresh", and "Unverifiable
# repository fails the refresh" (the RPM database trusts no key).
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

readonly UNSIGNED_REPOSITORY="/tmp/unsigned"

# Copies the metadata of one repository zypper has refreshed to UNSIGNED_REPOSITORY, without its signature and key.
copy_metadata_without_signature() {
  local raw_dir
  mkdir "${UNSIGNED_REPOSITORY}"
  for raw_dir in /var/cache/zypp/raw/*; do
    if [[ ! -s "${raw_dir}/repodata/repomd.xml" ]]; then continue; fi
    cp -R "${raw_dir}/repodata" "${UNSIGNED_REPOSITORY}/"
    break
  done
  rm -f "${UNSIGNED_REPOSITORY}/repodata/repomd.xml.asc" "${UNSIGNED_REPOSITORY}/repodata/repomd.xml.key"
}

# Prints the signing keys the RPM database trusts.
trusted_keys() {
  rpm -qa 'gpg-pubkey*' | sort
}

trusted_keys_are() {
  if [[ "$(trusted_keys)" != "$1" ]]; then
    echo "the keys the RPM database trusts changed" >&2
    return 1
  fi
}

# One repository beside the image's own answers nothing.
zypper --non-interactive addrepo http://127.0.0.1:9/ unavailable >/dev/null
run_install PACKAGES=bc REFRESHPOLICY=always
check "refreshPolicy=always with an unavailable repository fails" failed
check "refreshPolicy=always with an unavailable repository installs no bc" not_installed bc
zypper --non-interactive removerepo unavailable >/dev/null

zypper --non-interactive refresh
copy_metadata_without_signature
check "premise: the copied repository has an index" test -s "${UNSIGNED_REPOSITORY}/repodata/repomd.xml"
zypper --non-interactive addrepo "file://${UNSIGNED_REPOSITORY}" unsigned
configuration_before="$(zypp_configuration)"
keys_before="$(trusted_keys)"
run_install PACKAGES=bc
check "with an unsigned repository the feature fails" failed
check "with an unsigned repository no bc is installed" not_installed bc
check "with an unsigned repository the trusted keys are unchanged" trusted_keys_are "${keys_before}"
check "with an unsigned repository the zypp configuration is unchanged" \
  zypp_configuration_is "${configuration_before}"
zypper --non-interactive removerepo unsigned >/dev/null

# The image's repositories are signed by keys the RPM database no longer trusts. The metadata refreshed above goes
# first, so that the run has to verify what it downloads.
zypper --non-interactive clean --all >/dev/null
readarray -t keys < <(trusted_keys)
if [[ "${#keys[@]}" -gt 0 ]]; then rpm -e "${keys[@]}"; fi
check "premise: the RPM database trusts no key" trusted_keys_are ""
database_before="$(rpm_database)"
run_install PACKAGES=bc
check "with repositories signed by keys the image does not trust the feature fails" failed
check "with unverifiable repositories no bc is installed" not_installed bc
check "with unverifiable repositories the RPM database is unchanged, so no key is trusted" \
  rpm_database_is "${database_before}"

reportResults
