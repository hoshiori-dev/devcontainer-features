#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cd "${work}"
check "uv creates the documented project" uv init quarto-project
cd quarto-project
check "uv installs project-local Jupyter dependencies" uv add --dev jupyter
check "Quarto discovers project Jupyter" uv run quarto check jupyter
cat >example.qmd <<'DOC'
---
jupyter: python3
---

```{python}
print(1 + 1)
```
DOC
check "documented Python example renders" uv run quarto render example.qmd --to html
check "Python result is in the HTML" grep -q '>2<' example.html
check "project has its own Python environment" test -x .venv/bin/python
check "Jupyter dependency is recorded" grep -q jupyter pyproject.toml
reportResults
