#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the existing interpreter backs the CLI" "$HOME/.hf-cli/venv/bin/python" -c 'import sys; assert sys.base_prefix == "/usr/local"'
check "no distribution Python was added" bash -c '! dpkg-query -W python3 >/dev/null 2>&1'
check "the CLI survives removal of its temporary entry point" hf version
reportResults
