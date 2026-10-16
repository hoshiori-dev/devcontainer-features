#!/usr/bin/env bash
# Preserve user packages and files across changed and repeated selections.
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
check "second installation adds selections" run_installer PROFILE=standard LANGUAGES=zh,ja PACKAGES=csquotes
check "third installation preserves accumulated packages" run_installer PROFILE=basic LANGUAGES=none PACKAGES=
check "project editor settings remain unchanged" python3 -c 'from pathlib import Path; assert Path("settings.original.json").read_bytes() == Path(".vscode/settings.json").read_bytes()'
check "user editor settings remain unchanged" python3 -c 'import os; from pathlib import Path; assert Path(os.environ["HOME"], ".config/Code/User/settings.json").read_text() == "{\"editor.tabSize\":5}\n"'
check "user file survives repeated installation" grep -qx preserved "${HOME}/.TinyTeX/user-note.txt"
check "user-added package survives repeated installation" kpsewhich lipsum.sty
check "changed options add a package" kpsewhich csquotes.sty
cp documents/* .
check_common
check_ownership
check_chinese
check_japanese
report_installation_timing
reportResults
