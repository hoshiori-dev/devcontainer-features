#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=test/latex/installer.sh
source ./installer.sh

reject_distribution() (
  local saved
  saved="$(mktemp)"
  cp /etc/os-release "${saved}"
  trap 'sudo cp "${saved}" /etc/os-release; rm -f "${saved}"' EXIT
  printf 'ID=alpine\n' | sudo tee /etc/os-release >/dev/null
  if run_installer PROFILE=basic LANGUAGES=none > unsupported.log 2>&1; then return 1; fi
  grep -q 'unsupported distribution alpine' unsupported.log
)

reject_musl() (
  trap 'sudo rm -f /lib/ld-musl-latex-test' EXIT
  sudo touch /lib/ld-musl-latex-test
  if run_installer PROFILE=basic LANGUAGES=none > unsupported.log 2>&1; then return 1; fi
  grep -q 'musl is unsupported' unsupported.log
)

reject_architecture() (
  local fixture
  fixture="$(mktemp -d)"
  trap 'rm -rf "${fixture}"' EXIT
  printf '#!/bin/sh\nprintf "riscv64\\n"\n' > "${fixture}/uname"
  chmod +x "${fixture}/uname"
  if run_installer "PATH=${fixture}:${PATH}" PROFILE=basic LANGUAGES=none > unsupported.log 2>&1; then return 1; fi
  grep -q 'unsupported architecture' unsupported.log
)
check "Alpine distribution is rejected before dependencies" reject_distribution
check "musl libc is rejected before dependencies" reject_musl
check "unsupported architecture is rejected before dependencies" reject_architecture
reportResults
