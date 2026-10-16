#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh
printf '#!/bin/sh\nexit 0\n' > "${HOME}/.local/bin/latex-unrelated-fixture"
chmod +x "${HOME}/.local/bin/latex-unrelated-fixture"
check "shared PATH exposes no unrelated user commands" bash -c \
  '! PATH=/usr/local/share/latex/bin:/usr/local/bin:/usr/bin:/bin command -v latex-unrelated-fixture'
rm "${HOME}/.local/bin/latex-unrelated-fixture"
printf 'old user tree\n' > "${HOME}/.TinyTeX/old-user-note"
sudo useradd --create-home latex-remote-fixture
check "changing target user creates a separate installation" run_installer PROFILE=basic LANGUAGES=none \
  _REMOTE_USER=latex-remote-fixture _REMOTE_USER_HOME=/home/latex-remote-fixture
check "new TeX tree belongs to the new user" test \
  "$(sudo stat -c %u /home/latex-remote-fixture/.TinyTeX)" = "$(id -u latex-remote-fixture)"
check "old user's TeX files are preserved" grep -qx 'old user tree' "${HOME}/.TinyTeX/old-user-note"
check "new remote user manages packages without root" sudo runuser --user latex-remote-fixture -- \
  env HOME=/home/latex-remote-fixture PATH=/usr/local/share/latex/bin:/usr/local/bin:/usr/bin:/bin tlmgr install lipsum
reportResults
