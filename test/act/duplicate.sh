#!/bin/sh
# Install-twice test: act is installed with version 0.2.80 and defaultImage medium (VERSION, DEFAULTIMAGE), then with
# the defaults latest and none (VERSION__DEFAULT, DEFAULTIMAGE__DEFAULT), so the second install replaces the binary
# and keeps the configuration file. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 0.2.80 and the second selected the default latest; the
# configuration path only when the first selected medium and the second none.
if [ "${VERSION-}" != "0.2.80" ] || [ "${VERSION__DEFAULT-}" != "latest" ] \
  || [ "${DEFAULTIMAGE-}" != "medium" ] || [ "${DEFAULTIMAGE__DEFAULT-}" != "none" ]; then
  printf 'the paths under test would not run: expected version 0.2.80 then latest and defaultImage medium then' >&2
  printf ' none, got %s then %s and %s then %s\n' "${VERSION-}" "${VERSION__DEFAULT-}" "${DEFAULTIMAGE-}" \
    "${DEFAULTIMAGE__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the latest-release link names.
latest="$(latest_release)"
if [ "${latest}" = "0.2.80" ]; then
  echo 'the replace path would not run: the latest release is 0.2.80, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s, %s; second install: %s, %s; latest now: %s\n' "${VERSION}" "${DEFAULTIMAGE}" \
  "${VERSION__DEFAULT}" "${DEFAULTIMAGE__DEFAULT}" "${latest}"

check "command -v act resolves to /usr/local/bin/act" act_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than act whose name starts with "act" or ".act".
only_one_act() {
  for only_one_act_path in /usr/local/bin/act* /usr/local/bin/.act*; do
    if [ -e "${only_one_act_path}" ] && [ "${only_one_act_path}" != "/usr/local/bin/act" ]; then
      printf '  other file: %s\n' "${only_one_act_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/act ]
}
check "/usr/local/bin holds no file other than act whose name starts with act or .act" only_one_act
check "act --version reports the version the second install selected" act_reports_version "${latest}"
check "the remote user's configuration file still holds the medium lines after a later none" \
  config_holds_lines "${HOME}/.config/act/actrc" act
check "no temporary directory or staged file of the installs remains" no_install_leftovers

reportResults
