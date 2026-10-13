#!/bin/sh
# Scenario test_version_and_lock_arguments_alpine_3_22 (scenarios.json): this script runs install.sh with an apk on
# PATH that logs its arguments, and compares every apk call with the arguments written here. Spec scenarios "Omitted
# latest", "Omitted lockTimeout", "Default controls add no argument", "Native lock behavior is inherited" (no lock
# wait is passed), "Explicit lock wait reaches every apk call", "Lock wait works with a network timeout", "Latest is
# requested", "Both version options are requested" (apk receives both policies), "Policy behaves the same on every apk
# generation" (the same arguments on each image), "Earlier version policy and lock wait do not carry over", "Proxy
# environment is left as the build provides it", and "Configuration selection is left to the image" (the environment).
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"
# shellcheck source=/dev/null
. "$(dirname "$0")/installer.sh"

readonly CALL_LOG="/tmp/native-args"
readonly LOGGING_PATH="/tmp/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly ENVIRONMENT_LOG="/tmp/native-environment"
readonly STUB_PATH="/tmp/stub:/usr/sbin:/usr/bin:/sbin:/bin"
# What every call carries after its subcommand whatever the options hold. Every run below uses cleanup=none, so the
# cache directory is the feature's own and not a temporary one with a random name.
readonly AFTER_SUBCOMMAND="[--no-interactive] [--cache-dir] [/var/cache/apk-packages]"
readonly ADD="[add] ${AFTER_SUBCOMMAND} [--cache-max-age] [35791394]"
readonly UPDATE="[update] ${AFTER_SUBCOMMAND}"

# The apk calls logged since the log was last removed are exactly the lines $1; removes the log for the next run.
calls_are() {
  calls_are_found="$(cat "${CALL_LOG}")" || return 1
  rm "${CALL_LOG}"
  if [ "${calls_are_found}" != "$1" ]; then
    printf 'apk was called as:\n%s\nnot as:\n%s\n' "${calls_are_found}" "$1" >&2
    return 1
  fi
}

# Runs the command given with proxy variables and a variable that selects apk's configuration file in its environment.
with_proxy_environment() {
  env HTTPS_PROXY=http://upper.invalid:3128 https_proxy=http://lower.invalid:3128 HTTP_PROXY=http://upper.invalid:3128 \
    http_proxy=http://lower.invalid:3128 NO_PROXY=localhost,.upper.invalid no_proxy=localhost,.lower.invalid \
    ALL_PROXY=socks5://upper.invalid:1080 APK_CONFIG=/tmp/apk-config "$@"
}

# Both apk calls of the last run saw the proxy and APK_* variables of with_proxy_environment, each unchanged, and no
# other such variable.
apk_calls_saw_the_given_environment() {
  apk_calls_saw_the_given_environment_given="$(with_proxy_environment env | grep -Ei 'proxy|^APK_' | sort)" || return 1
  apk_calls_saw_the_given_environment_found="$(cat "${ENVIRONMENT_LOG}")" || return 1
  rm "${ENVIRONMENT_LOG}"
  apk_calls_saw_the_given_environment_expected="CALL
${apk_calls_saw_the_given_environment_given}
CALL
${apk_calls_saw_the_given_environment_given}"
  if [ "${apk_calls_saw_the_given_environment_found}" != "${apk_calls_saw_the_given_environment_expected}" ]; then
    printf 'the apk calls saw:\n%s\nnot:\n%s\n' "${apk_calls_saw_the_given_environment_found}" \
      "${apk_calls_saw_the_given_environment_expected}" >&2
    return 1
  fi
}

configuration_before="$(apk_configuration)"

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

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none
check "pv installs with networkTimeout, lockTimeout, latest, and upgradePackages omitted" exited_with 0
check "with the four options omitted no apk call receives a timeout, a lock wait, or a version policy" calls_are \
  "CALL ${UPDATE}
CALL ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LOCKTIMEOUT="" LATEST=false
check "pv installs with an empty lockTimeout and latest=false" exited_with 0
check "an empty lockTimeout and latest=false add no argument either" calls_are \
  "CALL ${UPDATE}
CALL ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LOCKTIMEOUT=7
check "pv installs with lockTimeout=7" exited_with 0
check "with lockTimeout=7 the refresh call and the install call receive --wait 7 and nothing else changes" calls_are \
  "CALL [--wait] [7] ${UPDATE}
CALL [--wait] [7] ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LOCKTIMEOUT=7 REFRESHPOLICY=always
check "pv installs with lockTimeout=7 and refreshPolicy=always" exited_with 0
check "with refreshPolicy=always both calls receive --wait 7" calls_are \
  "CALL [--wait] [7] ${UPDATE}
CALL [--wait] [7] ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LOCKTIMEOUT=7 REFRESHPOLICY=never
check "pv installs with lockTimeout=7 and refreshPolicy=never, from the indexes the earlier runs kept" exited_with 0
check "with refreshPolicy=never the offline index check and the install call receive --wait 7" calls_are \
  "CALL [--wait] [7] ${UPDATE} [--no-network]
CALL [--wait] [7] ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LOCKTIMEOUT=7 NETWORKTIMEOUT=9
check "pv installs with lockTimeout=7 and networkTimeout=9" exited_with 0
check "with both set every call receives --timeout 9 and --wait 7, each as its own setting" calls_are \
  "CALL [--timeout] [9] [--wait] [7] ${UPDATE}
CALL [--timeout] [9] [--wait] [7] ${ADD} [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LATEST=true
check "pv installs with latest=true" exited_with 0
check "with latest=true the install call receives --latest and the refresh call nothing" calls_are \
  "CALL ${UPDATE}
CALL ${ADD} [--latest] [--] [pv]"

run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LATEST=true UPGRADEPACKAGES=true
check "pv installs with latest=true and upgradePackages=true" exited_with 0
check "with both version options the install call receives --upgrade and --latest" calls_are \
  "CALL ${UPDATE}
CALL ${ADD} [--upgrade] [--latest] [--] [pv]"

pv_version="$(installed_version pv)"
run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none LATEST=true LOCKTIMEOUT=7
check "a first run with latest=true and lockTimeout=7 succeeds" exited_with 0
check "the first run passes --wait 7 and --latest" calls_are \
  "CALL [--wait] [7] ${UPDATE}
CALL [--wait] [7] ${ADD} [--latest] [--] [pv]"
run_install PATH="${LOGGING_PATH}" PACKAGES=pv CLEANUP=none
check "a second run with the same list and both options omitted succeeds" exited_with 0
check "the second run passes neither a version policy nor a lock wait" calls_are \
  "CALL ${UPDATE}
CALL ${ADD} [--] [pv]"
check "the second run does not lower pv from ${pv_version}" installed_in_version pv "${pv_version}"
check "no run wrote a setting to the apk configuration under /etc/apk" apk_configuration_is "${configuration_before}"
check "no run created the apk configuration file /lib/apk/config" test ! -e /lib/apk/config

# An apk that logs the proxy and APK_* variables it runs with and does nothing else: a real apk would try the proxies.
mkdir /tmp/stub
cat >/tmp/stub/apk <<STUB
#!/bin/sh
echo CALL >>${ENVIRONMENT_LOG}
env | grep -Ei 'proxy|^APK_' | sort >>${ENVIRONMENT_LOG}
STUB
chmod +x /tmp/stub/apk

record_run with_proxy_environment PATH="${STUB_PATH}" PACKAGES=pv "${INSTALLER}"
check "the run with proxy variables and APK_CONFIG in its environment reaches both apk calls" exited_with 0
check "with every option omitted both apk calls run with those variables unchanged and no other" \
  apk_calls_saw_the_given_environment
record_run with_proxy_environment PATH="${STUB_PATH}" PACKAGES=pv LATEST=true LOCKTIMEOUT=7 NETWORKTIMEOUT=9 \
  UPGRADEPACKAGES=true "${INSTALLER}"
check "the run with every control set and the same environment reaches both apk calls" exited_with 0
check "with every control set both apk calls still run with those variables unchanged and no other" \
  apk_calls_saw_the_given_environment

reportResults
