#!/bin/sh
# Scenario test_control_runs_alpine_3_22 (scenarios.json): this script runs install.sh several times with different
# controls in one container. Spec scenarios "Only package files are cleaned", "Cached metadata is explicitly selected",
# "Later controls apply to the second installation", "Existing image caches are preserved", "Native timeout is
# inherited", and "Explicit timeout reaches network operations".
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly UNRELATED_SENTINEL="/var/cache/feature-unrelated/sentinel"
readonly IMAGE_CACHE_SENTINEL="/var/cache/apk/sentinel"
readonly CALL_LOG="/tmp/native-args"
readonly LOGGING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# The file $1 still holds the line this script wrote to it.
sentinel_kept() {
  [ "$(cat "$1")" = keep ]
}

# The managed cache /var/cache/apk-packages holds a package index in either format apk writes.
managed_cache_holds_metadata() {
  for managed_cache_holds_metadata_file in /var/cache/apk-packages/APKINDEX.*.tar.gz /var/cache/apk-packages/*.adb; do
    if [ -f "${managed_cache_holds_metadata_file}" ]; then return 0; fi
  done
  echo "/var/cache/apk-packages holds no package index" >&2
  return 1
}

managed_cache_holds_no_metadata() {
  for managed_cache_holds_no_metadata_file in /var/cache/apk-packages/APKINDEX.*.tar.gz \
    /var/cache/apk-packages/*.adb; do
    if [ -f "${managed_cache_holds_no_metadata_file}" ]; then
      echo "/var/cache/apk-packages holds ${managed_cache_holds_no_metadata_file}" >&2
      return 1
    fi
  done
}

# Prints the logged apk calls that use the network: update and add.
network_calls() {
  grep -E '\[(update|install|add)\]' "${CALL_LOG}"
}

no_network_call_sets_a_timeout() {
  ! network_calls | grep -q '[Tt]imeout'
}

# Every network call carries apk's timeout option with the value $1.
every_network_call_has_timeout() {
  ! network_calls | grep -Fqv -- "[--timeout] [$1]"
}

no_network_call_changes_verification_or_retries() {
  ! network_calls | grep -Eq 'retries|sslverify|allow-untrusted|no-check-certificate'
}

configuration_before="$(apk_configuration)"
mkdir -p "${UNRELATED_SENTINEL%/*}"
echo keep >"${UNRELATED_SENTINEL}"
echo keep >"${IMAGE_CACHE_SENTINEL}"

run_install PACKAGES=tree CLEANUP=packages
check "tree installs with cleanup=packages" exited_with 0
check "tree is installed" installed tree
check "cleanup=packages leaves usable metadata in the managed cache" managed_cache_holds_metadata
run_install PACKAGES=tree CLEANUP=none REFRESHPOLICY=never
check "a later run with refreshPolicy=never and cleanup=none succeeds from the kept metadata" exited_with 0
check "cleanup=none leaves the metadata in place" managed_cache_holds_metadata
# A later default refresh and cleanup work after the earlier choice to keep the cache.
run_install PACKAGES=file CLEANUP=all
check "a later run with the default refresh and cleanup=all succeeds" exited_with 0
check "tree, which the earlier list named, is still installed" installed tree
check "file, which the later list named, is installed" installed file
check "cleanup=all removes the metadata" managed_cache_holds_no_metadata
check "no control value is written to the apk configuration" apk_configuration_is "${configuration_before}"
check "a cache directory the feature does not manage is untouched" sentinel_kept "${UNRELATED_SENTINEL}"
check "a file in the image's own cache /var/cache/apk is untouched" sentinel_kept "${IMAGE_CACHE_SENTINEL}"

# An apk that logs its arguments and then runs the image's apk.
mkdir /tmp/bin
cat >/tmp/bin/apk <<LOGGER
#!/bin/sh
printf 'CALL' >>${CALL_LOG}
for argument do printf ' [%s]' "\${argument}" >>${CALL_LOG}; done
printf '\n' >>${CALL_LOG}
exec $(command -v apk) "\$@"
LOGGER
chmod +x /tmp/bin/apk

run_install PATH="${LOGGING_PATH}" PACKAGES=pv NETWORKTIMEOUT=""
check "pv installs with an empty networkTimeout" exited_with 0
check "premise: the run with an empty networkTimeout made network calls" network_calls
check "with an empty networkTimeout no network call sets a timeout" no_network_call_sets_a_timeout
check "with an empty networkTimeout no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries
rm "${CALL_LOG}"
run_install PATH="${LOGGING_PATH}" PACKAGES=pv NETWORKTIMEOUT=1
check "pv installs with networkTimeout=1" exited_with 0
check "premise: the run with networkTimeout=1 made network calls" network_calls
check "with networkTimeout=1 every network call carries the timeout" every_network_call_has_timeout 1
check "with networkTimeout=1 no network call changes verification or retries" \
  no_network_call_changes_verification_or_retries

reportResults
