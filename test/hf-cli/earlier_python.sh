#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib
check "the earlier candidate is genuinely Python 3.9" /usr/local/python/current/bin/python3 -c 'import sys; assert sys.version_info[:2] == (3, 9)'
check "the later usable candidate backs the CLI" "$HOME/.hf-cli/venv/bin/python" -c 'import sys; assert sys.version_info[:2] == (3, 12); assert sys.base_prefix == "/usr/local"'
check "the old interpreter remains unchanged" /usr/bin/python3 -c 'import sys; assert sys.version_info[:2] == (3, 9)'
check "the selected interpreter remains accessible after cleanup" hf version
reportResults
