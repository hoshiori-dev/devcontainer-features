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
  backup_dir=""
  replacement_started=false
  replacement_complete=false
  mkdir -p "${fixture}/archive/.TinyTeX/bin/x86_64-linux" "${fixture}/home"
  printf '#!/bin/sh\nexit 0\n' > "${fixture}/archive/.TinyTeX/bin/x86_64-linux/tlmgr"
  chmod +x "${fixture}/archive/.TinyTeX/bin/x86_64-linux/tlmgr"
  tar -cJf "${fixture}/archive.tar.xz" -C "${fixture}/archive" .TinyTeX
  python3 - "${fixture}" "${mode}" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
mode = sys.argv[2]
digest = 'sha256:' + hashlib.sha256((root/'archive.tar.xz').read_bytes()).hexdigest()
if mode in ('mismatch', 'mismatch_existing'): digest = 'sha256:' + '0'*64
if mode == 'tls': digest = None
bundle = 'TinyTeX-2' if mode == 'full_existing' else 'TinyTeX-1'
assets = [{'name':bundle+'-linux-x86_64.tar.xz', 'digest':digest}]
if mode == 'missing': assets = []
if mode == 'publisher': assets.append({'name':'SHA256SUMS'})
(root/'release.json').write_text(json.dumps({'assets':assets}))
PY
  PROFILE=basic
  if [[ "${mode}" == full_existing ]]; then PROFILE=full; fi
  readonly PROFILE
  readonly REMOTE_USER=root
  readonly REMOTE_HOME="${fixture}/home"
  readonly TEX_DIR="${REMOTE_HOME}/.TinyTeX"
  readonly INSTALL_MARKER=.devcontainer-latex
  readonly RELEASE_METADATA=https://api.github.com/repos/rstudio/tinytex-releases/releases/tags/daily
  readonly RELEASE_DOWNLOAD=https://github.com/rstudio/tinytex-releases/releases/download/daily
  if [[ "${mode}" == *_existing || "${mode}" == rollback ]]; then
    mkdir -p "${TEX_DIR}"
    printf 'old tree\n' > "${TEX_DIR}/old-note"
    if [[ "${mode}" == identical_existing ]]; then
      cp -a "${fixture}/archive/.TinyTeX/." "${TEX_DIR}/"
      touch "${TEX_DIR}/${INSTALL_MARKER}"
    fi
  fi
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
      local bundle=TinyTeX-1
      if [[ "${PROFILE}" == full ]]; then bundle=TinyTeX-2; fi
      [[ "$3" == "${RELEASE_DOWNLOAD}/${bundle}-linux-x86_64.tar.xz" ]]
      cp "${fixture}/archive.tar.xz" "$2"
    fi
  }
  # shellcheck source=src/latex/scripts/bundle.sh
  source ./_feature/scripts/bundle.sh
  status=0
  if (
    # Load the production rollback handler without invoking the entry point.
    # shellcheck source=/dev/null
    source <(sed -n '/^cleanup() {/,/^}/p' ./_feature/install.sh)
    trap cleanup EXIT
    install_bundle
    if [[ "${mode}" == rollback ]]; then fail "simulated package setup failure"; fi
    # The production cleanup handler reads this flag through the sourced definition.
    # shellcheck disable=SC2034
    replacement_complete=true
  ) > "${fixture}/result.log" 2>&1; then status=0; else status=$?; fi
  cat "${fixture}/result.log"
  case "${mode}" in
    valid) [[ "${status}" == 0 && -f "${TEX_DIR}/${INSTALL_MARKER}" ]] ;;
    valid_existing | full_existing | identical_existing) [[ "${status}" == 0 && ! -e "${TEX_DIR}/old-note" ]] ;;
    mismatch_existing | rollback) [[ "${status}" != 0 ]] && grep -qx 'old tree' "${TEX_DIR}/old-note" ;;
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
check "verified archive replaces an unmanaged tree" bundle_fixture valid_existing
check "verification failure preserves the old tree" bundle_fixture mismatch_existing
check "setup failure restores the old tree" bundle_fixture rollback
check "full replacement downloads TinyTeX-2 directly" bundle_fixture full_existing
check "identical installation also replaces the existing tree" bundle_fixture identical_existing
reportResults
