#!/bin/sh
# Scenario install_if_and_whitespace_alpine_3_24 (scenarios.json): spec scenarios "Install-if packages
# follow their conditions", "Spaces and empty entries are ignored", and "Caches are removed". The
# value has spaces, a tab, and an empty entry; jq-doc is installed only through its install-if
# conditions, jq and docs.
# POSIX sh with the stand-in in checks.sh: the Alpine images ship no bash, which the CLI's
# dev-container-features-test-lib needs.
set -eu

# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

check "jq is installed" installed jq
check "docs is installed" installed docs
check "jq runs" jq --version
check "jq-doc, whose install-if conditions are met, is installed" installed jq-doc
check "jq is a line of apk's world" in_world jq
check "docs is a line of apk's world" in_world docs
check "jq-doc is not in apk's world" sh -c '! grep -Fqx jq-doc /etc/apk/world'
check "/var/cache/apk is left as it was, empty" cache_left_empty
check "no temporary directory of the feature is left" no_temporary_dir

reportResults
