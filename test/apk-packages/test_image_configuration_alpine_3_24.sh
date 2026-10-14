#!/bin/sh
# Scenario test_image_configuration_alpine_3_24 (scenarios.json): this script writes the apk configuration file
# /etc/apk/config, as an image could ship it, and then runs install.sh. Only apk 3 reads that file, so the script asks
# the image's apk for its generation and asserts on apk 3 what the setting does, and on apk 2 that the file has no
# effect. Spec scenarios "Native lock behavior is inherited" (an image wait setting), "Image wait setting is overridden
# for the invocation", "Image configuration that disables caching keeps nothing", and "Configuration selection is left
# to the image" (the file).
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

# The feature's cache /var/cache/apk-packages holds no package index, in either format apk writes, and no package
# file.
managed_cache_holds_no_index_or_package_file() {
  for managed_cache_holds_no_index_or_package_file_path in /var/cache/apk-packages/APKINDEX.*.tar.gz \
    /var/cache/apk-packages/*.adb /var/cache/apk-packages/*.apk; do
    if [ -e "${managed_cache_holds_no_index_or_package_file_path}" ]; then
      echo "/var/cache/apk-packages holds ${managed_cache_holds_no_index_or_package_file_path}" >&2
      return 1
    fi
  done
}

managed_cache_holds_an_index() {
  for managed_cache_holds_an_index_file in /var/cache/apk-packages/APKINDEX.*.tar.gz /var/cache/apk-packages/*.adb; do
    if [ -f "${managed_cache_holds_an_index_file}" ]; then return 0; fi
  done
  echo "/var/cache/apk-packages holds no package index" >&2
  return 1
}

apk_version="$(apk --version)"
case "${apk_version}" in
  "apk-tools 3."*) reads_configuration=true ;;
  "apk-tools 2."*) reads_configuration=false ;;
  *)
    echo "unexpected apk generation: ${apk_version}" >&2
    exit 1
    ;;
esac

check "premise: the image ships no /etc/apk/config" test ! -e /etc/apk/config
check "premise: the image ships no /lib/apk/config" test ! -e /lib/apk/config

echo "wait 60" >/etc/apk/config
configuration_with_wait="$(apk_configuration)"

hold_apk_lock 4
run_install PACKAGES=tree
wait
if [ "${reads_configuration}" = "true" ]; then
  check "apk 3: with lockTimeout omitted the image's wait applies, and the run succeeds after the release" \
    exited_with 0
  check "apk 3: tree is installed" installed tree
else
  check "apk 2: the file has no effect, and with lockTimeout omitted a held lock fails the run" install_failed
  check "apk 2: tree is not installed" not_installed tree
fi

# The lock stays held for 15 seconds: under the image's wait of 60 the run would end at the release and succeed, so a
# failure shows that the wait of lockTimeout applied.
hold_apk_lock 15
started="$(date +%s)"
run_install PACKAGES=pv LOCKTIMEOUT=2
finished="$(date +%s)"
wait
check "with lockTimeout=2 and the image's wait of 60 a run fails when the lock is held for 15 seconds" install_failed
check "the run did not fail before 2 seconds had passed" test "$((finished - started))" -ge 2
check "the run failed before the lock was released" test "$((finished - started))" -lt 15
check "pv is not installed" not_installed pv
check "the image's configuration file is unchanged" apk_configuration_is "${configuration_with_wait}"

echo "no-cache" >/etc/apk/config
configuration_without_cache="$(apk_configuration)"

run_install PACKAGES=file CLEANUP=none
check "file installs with cleanup=none under an image configuration holding no-cache" exited_with 0
check "file is installed" installed file
if [ "${reads_configuration}" = "true" ]; then
  check "apk 3: with cleanup=none the feature's cache holds neither an index nor a package file" \
    managed_cache_holds_no_index_or_package_file
else
  check "apk 2: the file has no effect, and with cleanup=none the feature's cache holds an index" \
    managed_cache_holds_an_index
  check "apk 2: with cleanup=none the feature's cache holds the package file of file" \
    test -n "$(find /var/cache/apk-packages -name 'file-[0-9]*.apk')"
fi
rm -rf /var/cache/apk-packages

run_install PACKAGES=less CLEANUP=packages
check "less installs with cleanup=packages under an image configuration holding no-cache" exited_with 0
check "less is installed" installed less
if [ "${reads_configuration}" = "true" ]; then
  check "apk 3: with cleanup=packages the feature's cache holds neither an index nor a package file" \
    managed_cache_holds_no_index_or_package_file
else
  check "apk 2: the file has no effect, and with cleanup=packages the feature's cache holds an index" \
    managed_cache_holds_an_index
fi
check "the image's configuration file is unchanged by both runs" apk_configuration_is "${configuration_without_cache}"
check "no run created /lib/apk/config" test ! -e /lib/apk/config

reportResults
