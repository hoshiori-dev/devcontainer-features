#!/usr/bin/env bash
# Scenario test_controls_selection_0 (scenarios.json): the devcontainer CLI installs the feature with the list
# bc-debuginfo, which only the disabled repository fedora-debuginfo offers, enableRepositories=" fedora-debuginfo ,",
# disableRepositories=fedora-cisco-openh264, best=true, and parallelDownloads=2. Spec scenarios "Disabled repository is
# enabled for the invocation" and "Both lists apply together", with the options as the CLI hands them to install.sh at
# image build time.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/installer.sh"

# The image lists the repository $1 with the state $2, enabled or disabled.
repository_is() {
  local states
  states="$(repository_states)"
  grep --line-regexp --quiet "$1 $2" <<<"${states}"
}

check "bc-debuginfo, which only the temporarily enabled fedora-debuginfo offers, is installed" installed bc-debuginfo
check "fedora-debuginfo is still disabled in the image" repository_is fedora-debuginfo disabled
check "fedora-cisco-openh264, left out for the installation, is still enabled in the image" \
  repository_is fedora-cisco-openh264 enabled
check "the default cleanup=all left no metadata, also none of fedora-debuginfo" no_metadata

reportResults
