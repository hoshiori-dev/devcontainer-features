#!/usr/bin/env bash
# Scenario (build): the Dockerfile enables EPEL on almalinux:9 before the feature runs and marks epel.repo. The feature
# adds no repository, leaves the marked file as it is, and installs apptainer from the configured EPEL.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

installed_from_epel() {
  local from
  from="$(rpm -q --qf '%{FROM_REPO}' apptainer 2>/dev/null || true)"
  # Older rpm has no FROM_REPO tag; dnf records the repository too.
  if [[ -z "${from}" || "${from}" == "(none)" ]]; then
    from="$(as_root dnf repoquery --installed --qf '%{from_repo}\n' apptainer)" || return
  fi
  if [[ "${from}" != epel ]]; then
    printf '%s\n' "apptainer was installed from '${from}', expected epel" >&2
    return 1
  fi
}

check "the marked epel.repo is left as the image wrote it" grep -qx '# preconfigured-by-scenario' /etc/yum.repos.d/epel.repo
check "EPEL is defined once" source_defined_once
check "apptainer was installed from the configured EPEL" installed_from_epel
check "apptainer runs for the remote user" apptainer --version
check "the non-setuid package is installed and no file under ${APPTAINER_LIBEXEC_DIR} is setuid" non_setuid

reportResults
