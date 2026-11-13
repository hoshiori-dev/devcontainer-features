#!/bin/sh
# Install-twice test: opentofu is installed with version 1.12.12 (VERSION), then with the default latest
# (VERSION__DEFAULT), so the second install replaces the binary. POSIX sh, because alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

# The replace path runs only when the first install was 1.12.12 and the second selected the default latest.
if [ "${VERSION-}" != "1.12.12" ] || [ "${VERSION__DEFAULT-}" != "latest" ]; then
  printf 'the replace path would not run: expected version 1.12.12 then latest, got %s then %s\n' \
    "${VERSION-}" "${VERSION__DEFAULT-}" >&2
  exit 1
fi

# Computed at run time: the second install took whatever release the latest-release link names.
latest="$(latest_release)"
if [ "${latest}" = "1.12.12" ]; then
  echo 'the replace path would not run: the latest release is 1.12.12, the version of the first install' >&2
  exit 1
fi
printf 'first install: %s; second install: %s; latest now: %s\n' "${VERSION}" "${VERSION__DEFAULT}" "${latest}"

check "command -v tofu resolves to /usr/local/bin/tofu" tofu_resolves_to_usr_local_bin

# /usr/local/bin holds no file other than tofu whose name contains "tofu".
only_one_tofu() {
  for only_one_tofu_path in /usr/local/bin/*tofu* /usr/local/bin/.*tofu*; do
    if [ -e "${only_one_tofu_path}" ] && [ "${only_one_tofu_path}" != "/usr/local/bin/tofu" ]; then
      printf '  other file: %s\n' "${only_one_tofu_path}"
      return 1
    fi
  done
  [ -f /usr/local/bin/tofu ]
}
check "/usr/local/bin holds no file other than tofu whose name contains tofu" only_one_tofu
check "tofu version reports the release the second install selected" tofu_reports_version "${latest}"
check "no temporary directory or staged file of the installs remains" no_install_leftovers

reportResults
