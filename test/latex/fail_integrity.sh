#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source dev-container-features-test-lib

# Exercise the shipped download/extraction step with controlled release assets and no network.
bundle_fixture() (
  set -euo pipefail
  mode="$1"
  fixture="$(mktemp -d)"
  work_dir=""
  trap 'rm -rf "${fixture}" "${work_dir}"' EXIT
  mkdir -p "${fixture}/archive/.TinyTeX/bin/x86_64-linux" "${fixture}/home"
  printf '#!/bin/sh\nexit 0\n' > "${fixture}/archive/.TinyTeX/bin/x86_64-linux/tlmgr"
  chmod +x "${fixture}/archive/.TinyTeX/bin/x86_64-linux/tlmgr"
  tar -cJf "${fixture}/archive.tar.xz" -C "${fixture}/archive" .TinyTeX
  python3 - "${fixture}" "${mode}" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
digest = 'sha256:' + hashlib.sha256((root/'archive.tar.xz').read_bytes()).hexdigest()
if mode == 'mismatch': digest = 'sha256:' + '0'*64
if mode == 'tls': digest = None
assets = [{'name':'TinyTeX-1-linux-x86_64.tar.xz', 'digest':digest}]
if mode == 'missing': assets = []
if mode == 'publisher': assets.append({'name':'SHA256SUMS'})
(root/'release.json').write_text(json.dumps({'assets':assets}))
PY
  readonly PROFILE=basic
  readonly REMOTE_USER=root
  readonly REMOTE_HOME="${fixture}/home"
  readonly TEX_DIR="${REMOTE_HOME}/.TinyTeX"
  readonly INSTALL_MARKER=.devcontainer-latex
  readonly RELEASE_METADATA=https://api.github.com/repos/rstudio/tinytex-releases/releases/tags/daily
  readonly RELEASE_DOWNLOAD=https://github.com/rstudio/tinytex-releases/releases/download/daily
  arch=x86_64
  fresh=false
  tex_bin=""
  log() { printf 'latex: %s\n' "$*"; }
  fail() { printf 'latex: error: %s\n' "$*" >&2; exit 1; }
  as_user() { "$@"; }
  fetch() {
    [[ "$1" == --output ]]
    if [[ "$3" == "${RELEASE_METADATA}" ]]; then
      cp "${fixture}/release.json" "$2"
    else
      [[ "$3" == "${RELEASE_DOWNLOAD}/TinyTeX-1-linux-x86_64.tar.xz" ]]
      cp "${fixture}/archive.tar.xz" "$2"
    fi
  }
  # shellcheck source=src/latex/scripts/bundle.sh
  source ./_feature/scripts/bundle.sh
  status=0
  if (install_bundle) > "${fixture}/result.log" 2>&1; then status=0; else status=$?; fi
  cat "${fixture}/result.log"
  case "${mode}" in
    valid) [[ "${status}" == 0 && -f "${TEX_DIR}/${INSTALL_MARKER}" ]] ;;
    tls) [[ "${status}" == 0 ]] && grep -q 'trusting HTTPS transport only' "${fixture}/result.log" ;;
    mismatch) [[ "${status}" != 0 && ! -e "${TEX_DIR}" ]] \
      && grep -q 'bundle digest mismatch' "${fixture}/result.log" ;;
    missing | publisher) [[ "${status}" != 0 && ! -e "${TEX_DIR}" ]] ;;
  esac
)
check "verified archive is extracted successfully" bundle_fixture valid
check "digest mismatch fails before extraction" bundle_fixture mismatch
check "missing asset metadata fails before extraction" bundle_fixture missing
check "unsupported publisher verification fails closed" bundle_fixture publisher
check "absence of verification data logs TLS-only trust" bundle_fixture tls
reportResults
