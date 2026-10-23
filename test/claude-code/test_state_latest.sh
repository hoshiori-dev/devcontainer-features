#!/usr/bin/env bash
set -euo pipefail
export EXPECTED_CLAUDE_VERSION=latest
exec bash "$(dirname "$0")/test_state.sh"
