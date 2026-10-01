#!/usr/bin/env bash
# Scenario pinned_version (scenarios.json): spec scenario "Pinned release", with a release older
# than the latest one, so a pass cannot come from following `latest`.
set -e

# shellcheck source=/dev/null
source dev-container-features-test-lib

reports_pinned_release() {
  [ "$("$1" --version)" = "hf-mount 0.13.0" ]
}

check "hf-mount reports the pinned release" reports_pinned_release hf-mount
check "hf-mount-nfs comes from the pinned release" reports_pinned_release hf-mount-nfs
check "hf-mount-fuse comes from the pinned release" reports_pinned_release hf-mount-fuse

reportResults
