#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh

preserve_unmanaged_tree() {
  mv "${HOME}/.TinyTeX/.devcontainer-latex" "${HOME}/.TinyTeX/.saved-marker"
  printf 'preserved\n' > "${HOME}/.TinyTeX/conflict-note"
  local status=0
  run_installer PROFILE=basic LANGUAGES=none > conflict.log 2>&1 || status=$?
  mv "${HOME}/.TinyTeX/.saved-marker" "${HOME}/.TinyTeX/.devcontainer-latex"
  [[ "${status}" != 0 ]] && grep -q 'unmanaged TinyTeX tree' conflict.log \
    && grep -qx preserved "${HOME}/.TinyTeX/conflict-note"
}
check "unmanaged tree fails without deleting user files" preserve_unmanaged_tree
preserve_cross_year_tree() {
  local status=0
  run_installer PROFILE=basic LANGUAGES=none PACKAGES=kantlipsum \
    CTANMIRROR=https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/2025/tlnet-final \
    > cross-year.log 2>&1 || status=$?
  cat cross-year.log
  [[ "${status}" != 0 ]] && grep -q 'matching TeX Live year' cross-year.log \
    && grep -qx preserved "${HOME}/.TinyTeX/conflict-note" && kpsewhich article.cls
}
check "cross-year repository fails without replacing the tree" preserve_cross_year_tree
reportResults
