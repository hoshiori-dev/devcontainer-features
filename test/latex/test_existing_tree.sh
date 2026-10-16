#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh
rm "${HOME}/.TinyTeX/.devcontainer-latex"
printf 'discarded\n' > "${HOME}/.TinyTeX/unmanaged-note"
check "unmanaged installation is replaced" run_installer PROFILE=basic LANGUAGES=none
check "old unmanaged files are discarded" test ! -e "${HOME}/.TinyTeX/unmanaged-note"
check "new installation belongs to the remote user" test "$(stat -c %u "${HOME}/.TinyTeX")" = "$(id -u)"
reportResults
