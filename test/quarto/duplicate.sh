#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "duplicate test starts from an exact version" test "${VERSION}" = 1.9.38
check "second installation selects the default" test "${VERSION__DEFAULT}" = latest
# The current stable API response is time-dependent, matching the installer's source of latest.
latest="$(curl --proto '=https' --proto-redir '=https' -fsSL \
  https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | jq -r '.tag_name | ltrimstr("v")')"
check "last installation selects the current stable version" test "$(quarto --version)" = "${latest}"
check "system command targets the managed tree" test "$(readlink /usr/local/bin/quarto)" = /opt/quarto/bin/quarto
check "installed version matches its marker" \
  test "$(quarto --version)" = "$(cat /opt/quarto/.devcontainer-feature-quarto)"
check "installation belongs to root" test "$(stat -c %u /opt/quarto)" = 0
check "installation is not writable by other users" \
  bash -c '! find /opt/quarto ! -type l -perm /022 -print -quit | grep -q .'
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
printf '# Hello Quarto\n\nA simple document.\n' >"${work}/example.qmd"
check "document without executable code renders to HTML" quarto render "${work}/example.qmd" --to html
check "HTML is nonempty" test -s "${work}/example.html"
reportResults
