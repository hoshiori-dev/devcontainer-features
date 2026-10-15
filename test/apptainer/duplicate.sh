#!/usr/bin/env bash
# Install-twice test: apptainer is installed twice on the same image. The feature has no options, so both installs are
# the default; the second must leave one installation, one source definition, and the same version.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

# The version the feature's source offers when the test runs (helpers.sh, source_candidate).
# A failed query leaves it empty, so the labeled check reports it instead of set -e ending the script.
candidate="$(source_candidate || true)"

check "apptainer reports the version the source ships after two installs (${candidate:-none})" \
  version_reports "${candidate}"
check "the source is defined once after two installs" source_defined_once
check "the source definition is the one the feature writes for this image" source_is_expected
check "the key file holds only the pinned key" key_is_pinned
check "the non-setuid package is installed and no file under ${APPTAINER_LIBEXEC_DIR} is setuid" non_setuid
check "no temporary install directory remains" no_temporary_dir

reportResults
