# shellcheck shell=bash

test_dir="${test_dir-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Invokes the copied installer as root with the requested version and fixture PATH.
run_installer() {
  env PATH="${FIXTURE_DIR}/bin:${PATH}" FIXTURE_DIR="${FIXTURE_DIR}" VERSION="$1" \
    bash "${test_dir}/_feature/install.sh" >"${FIXTURE_DIR}/output" 2>&1
}

# Creates a small release whose executable can fail only after activation when $2 is active_failure.
make_release() {
  local version="$1"
  local behavior="${2-normal}"
  local arch
  mkdir -p "${FIXTURE_DIR}/${version}/bundle/quarto/bin"
  cat >"${FIXTURE_DIR}/${version}/bundle/quarto/bin/quarto" <<SCRIPT
#!/usr/bin/env bash
if [[ '${behavior}' == incompatible ]]; then exit 1; fi
if [[ '${behavior}' == active_failure && "\$0" == /usr/local/bin/quarto ]]; then exit 1; fi
printf '%s\\n' '${version}'
SCRIPT
  chmod +x "${FIXTURE_DIR}/${version}/bundle/quarto/bin/quarto"
  tar -czf "${FIXTURE_DIR}/${version}/archive.tar.gz" -C "${FIXTURE_DIR}/${version}/bundle" quarto
  for arch in amd64 arm64; do
    printf '%s  quarto-%s-linux-%s.tar.gz\n' \
      "$(sha256sum "${FIXTURE_DIR}/${version}/archive.tar.gz" | cut -d ' ' -f 1)" "${version}" "${arch}"
  done >"${FIXTURE_DIR}/${version}/checksums.txt"
}

# Tests failures against a healthy version, checking both the diagnostic and preservation of the CLI.
rejects_and_preserves() {
  local mode="$1"
  local diagnostic="$2"
  printf '%s\n' "${mode}" >"${FIXTURE_DIR}/mode"
  if run_installer 1.2.4; then cat "${FIXTURE_DIR}/output"; return 1; fi
  cat "${FIXTURE_DIR}/output"
  grep -q "${diagnostic}" "${FIXTURE_DIR}/output" && [[ "$(quarto --version)" == 1.2.3 ]]
}
