# shellcheck shell=bash
# Downloads and verifies a new bundle on every invocation, backing up any previous target tree.
install_bundle() {
  local bundle=TinyTeX
  local asset
  # The entry point sets the validated archive architecture before sourcing this library.
  # shellcheck disable=SC2154
  local architecture="${arch}"
  local digest
  case "${PROFILE}" in basic) bundle=TinyTeX-1 ;; full) bundle=TinyTeX-2 ;; esac
  fresh=true
  asset="${bundle}-linux-${architecture}.tar.xz"
  work_dir="$(mktemp --directory)"
  chmod 0755 "${work_dir}"
  log "resolving ${asset} from ${RELEASE_METADATA}"
  fetch --output "${work_dir}/release.json" "${RELEASE_METADATA}" \
    || fail "cannot resolve TinyTeX release; check GitHub availability"
  digest="$(python3 - "${work_dir}/release.json" "${asset}" <<'PY'
import json, re, sys
assets = json.load(open(sys.argv[1]))['assets']
asset = next(a for a in assets if a['name'] == sys.argv[2])
# New publisher verification formats require explicit support, rather than silently skipping them.
verification = [a['name'] for a in assets if re.search(r'(sha\d*|checksum|\.sig$|\.asc$)', a['name'], re.I)]
if verification:
    raise SystemExit('Publisher verification assets found; update this feature to verify: ' + ', '.join(verification))
digest = asset.get('digest') or ''
if digest and not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
    raise SystemExit('Unsupported asset digest')
print(digest)
PY
)" || fail "cannot resolve bundle verification metadata; inspect the upstream release"
  log "downloading ${RELEASE_DOWNLOAD}/${asset}"
  fetch --output "${work_dir}/bundle.tar.xz" "${RELEASE_DOWNLOAD}/${asset}" \
    || fail "bundle download failed; retry when the upstream release is available"
  if [[ -n "${digest}" ]]; then
    log "verifying GitHub SHA-256 digest for ${asset}"
    printf '%s  %s\n' "${digest#sha256:}" "${work_dir}/bundle.tar.xz" | sha256sum --check \
      || fail "bundle digest mismatch; retry against a consistent daily release"
  else
    log "upstream publishes no checksum or signature; trusting HTTPS transport only"
  fi
  if [[ -e "${TEX_DIR}" || -L "${TEX_DIR}" ]]; then
    backup_dir="$(mktemp --directory "${REMOTE_HOME}/.TinyTeX-backup.XXXXXX")"
    rmdir "${backup_dir}"
    mv -- "${TEX_DIR}" "${backup_dir}"
  fi
  # The entry point uses this flag to restore the old tree on failure.
  # shellcheck disable=SC2034
  replacement_started=true
  log "extracting verified bundle to ${TEX_DIR} as ${REMOTE_USER}"
  as_user tar --extract --file "${work_dir}/bundle.tar.xz" --directory "${REMOTE_HOME}" --no-same-owner \
    || fail "cannot extract TinyTeX; check space and home permissions"
  tex_bin="${TEX_DIR}/bin/${architecture}-linux"
  if [[ "${architecture}" == arm64 ]]; then tex_bin="${TEX_DIR}/bin/aarch64-linux"; fi
  [[ -x "${tex_bin}/tlmgr" ]] || fail "TinyTeX tree is unusable; restore it or rebuild from a clean base"
  as_user "${tex_bin}/tlmgr" --version || fail "tlmgr cannot run; check the selected platform and tree"
  if ${fresh}; then
    as_user touch "${TEX_DIR}/${INSTALL_MARKER}"
    as_user "${tex_bin}/tlmgr" postaction install script xetex || fail "XeTeX setup failed"
  fi
}
