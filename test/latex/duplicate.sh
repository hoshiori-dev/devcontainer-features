#!/usr/bin/env bash
# The last installation replaces the tree while preserving editor settings.
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh
# shellcheck source=test/latex/checks.sh
source ./checks.sh
mkdir -p .vscode
printf '{"editor.tabSize":3}\n' > .vscode/settings.json
cp .vscode/settings.json settings.original.json
mkdir -p "${HOME}/.config/Code/User"
printf '{"editor.tabSize":5}\n' > "${HOME}/.config/Code/User/settings.json"
printf 'preserved\n' > "${HOME}/.TinyTeX/user-note.txt"
check "remote user can add a package without sudo" tlmgr install lipsum
check "second installation replaces the tree with current selections" run_installer PROFILE=standard LANGUAGES=zh,ja PACKAGES=csquotes
check "second installation discards old user files" test ! -e "${HOME}/.TinyTeX/user-note.txt"
check "current selection adds its requested package" kpsewhich csquotes.sty
printf 'discarded\n' > "${HOME}/.TinyTeX/second-note.txt"
check "third installation replaces the tree with basic" run_installer PROFILE=basic LANGUAGES=none PACKAGES=
check "project editor settings remain unchanged" python3 -c 'from pathlib import Path; assert Path("settings.original.json").read_bytes() == Path(".vscode/settings.json").read_bytes()'
check "user editor settings remain unchanged" python3 -c 'import os; from pathlib import Path; assert Path(os.environ["HOME"], ".config/Code/User/settings.json").read_text() == "{\"editor.tabSize\":5}\n"'
check "smaller selection discards old files" test ! -e "${HOME}/.TinyTeX/second-note.txt"
check "smaller selection removes the extra package" bash -c '! tlmgr info --only-installed --data name | grep -qx csquotes'
cp documents/* .
check_common
check_ownership
report_installation_timing
reportResults
