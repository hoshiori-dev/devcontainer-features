#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# Computed test paths cannot be resolved by shellcheck.
# shellcheck source=/dev/null
source "$(dirname "$0")/assertions.sh"
check "tooling changed the remote user UID" test "$(id -u)" != 23456
check "remote user no longer owns the tool" test "$(stat -c %u "${TOOL_ENV}")" != "$(id -u)"
check "colab runs after UID change" reports_release 0.7.2
check "unrelated build-time tool is preserved" pycowsay hello
check "remote user can reinstall the CLI" uv tool install --reinstall google-colab-cli==0.7.2
check "reinstalled colab still runs" reports_release 0.7.2
check "remote user can uninstall the CLI" uv tool uninstall google-colab-cli
check "unrelated tool remains after uninstall" pycowsay hello
check "remote user can add a CLI tool" uv tool install google-colab-cli==0.7.2
check "added colab runs" reports_release 0.7.2
reportResults
