#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "extra package lipsum is available" kpsewhich lipsum.sty
check "extra package csquotes is available" kpsewhich csquotes.sty
check "custom repository is retained for user operations" bash -c \
  'tlmgr option repository | grep -F "https://ctan.tikz.jp/systems/texlive/tlnet"'
check "user installs another package without sudo" tlmgr install kantlipsum
check "new package is usable" kpsewhich kantlipsum.sty
reportResults
