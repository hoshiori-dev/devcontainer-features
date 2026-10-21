#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"
cat >example.qmd <<'DOC'
---
format:
  pdf:
    latex-tinytex: false
---

# Hello Quarto

This document uses the existing TeX environment.
DOC
check "documented LaTeX composition renders" quarto render example.qmd --to pdf
check "PDF is nonempty" test -s example.pdf
tex_path="$(readlink -f "$(command -v pdflatex)")"
check "PDF uses the companion TeX installation" test "${tex_path#"${HOME}/.TinyTeX/"}" != "${tex_path}"
reportResults
