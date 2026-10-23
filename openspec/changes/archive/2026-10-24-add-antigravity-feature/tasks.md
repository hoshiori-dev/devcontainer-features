# Tasks

## 1. State-path feasibility

- [x] 1.1 Run the verified 1.4.6 executable offline as a non-root user with a fresh home (version, help, local
      subcommands, a bounded unauthenticated start, and a file-access trace); verify which directories it writes and
      reads, that directory links survive its writes and atomic replacements, which store `XDG_CONFIG_HOME` moves, and
      that `AGY_CLI_DISABLE_AUTO_UPDATE=true` stops the updater.

## 2. Installation

- [x] 2.1 Scaffold `antigravity` with `just new-feature antigravity`; write `devcontainer-feature.json` (version
      `1.0.0`, no options, `antigravity-${devcontainerId}` volume at `/var/lib/antigravity`, `onCreateCommand`,
      `containerEnv` disabling auto-update, `installsAfter` common-utils) and verify `just validate` accepts it.
- [x] 2.2 Implement `install.sh`: platform and musl detection, untested-target warning, prerequisites, manifest
      resolution with prefix, version and SHA-512 checks, staged execution in an isolated home before replacement,
      skipping an unchanged version, `agy` on the default PATH without the upstream installer or `agy install`, and
      build-time state links; verify with `test.sh` and `duplicate.sh` on every compatibility image.
- [x] 2.3 Write `compatibility.json` (Debian 12 and Ubuntu 24.04 on amd64 and arm64), `fail_installation` (prefix,
      missing digest, digest mismatch, unusable payload, uncovered system and CPU, unchanged working CLI) and
      `test_untested` (a covered untested distribution warns and installs); verify both scenarios pass.

## 3. State initialization

- [x] 3.1 Implement `initialize.sh`: mount, effective home and XDG paths, link reuse and creation, conflict failures
      that preserve content, private ownership and modes, bounded repair through noninteractive sudo, and user access
      probes; verify with the `test_state` scenario (healthy volume without a scan, missing mount, conflicts, new home,
      XDG root, changed UID, unavailable repair, synthetic atomic credential and plugin-secret writes, Gemini
      coexistence, backend selection preserved, changed release preserving state).
- [x] 3.2 Add the node composition scenarios (explicit, partial, empty options) and verify Node keeps its own settings
      while `agy` and the initializer stay usable.
- [x] 3.3 Add `test/antigravity/manual/state_persistence.sh` and run it against a locally built image to verify
      two-container persistence of synthetic files, private permissions, and project isolation.

## 4. Documentation

- [x] 4.1 Write `NOTES.md` (installation route, mapped paths, authentication choices and file boundaries,
      consumer-managed stores, overrides outside the guarantee, recovery and migration, editor routes with the terminal
      fallback); run `just docs` and translate the root feature-list change into `README.zh.md`; verify
      `just docs-check` passes.

## 5. Validation

- [x] 5.1 Run `just check`, `just test antigravity`, and `just test-scenarios antigravity`, and record the results for
      the PR's Validation section.
