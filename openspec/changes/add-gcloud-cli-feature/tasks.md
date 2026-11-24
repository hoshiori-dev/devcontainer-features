# Tasks

## 1. Feature Metadata and Core Scripts

- [x] 1.1 Create `src/gcloud-cli/devcontainer-feature.json` with version `1.0.0`, `version` and `components` options,
      `common-utils` ordering, named volume mount, and `onCreateCommand`; verify `just spec-check` passes.
- [x] 1.2 Implement `src/gcloud-cli/install.sh` (Bash) with option/platform validation, Plan A signed APT and DNF
      routes, Plan B archive fallback with warning, cross-route component mapping, idempotent reinstall, build-time
      state prep, and cache/temp cleanup; verify `shellcheck` passes.
- [x] 1.3 Implement `src/gcloud-cli/initialize.sh` (Bash) with mount check, `CLOUDSDK_CONFIG` and home link conflict
      checks, state symlink protection, bounded readiness, mode-only repair without `sudo`, and confined `--repair`;
      verify `shellcheck` passes.

## 2. Documentation

- [x] 2.1 Write `src/gcloud-cli/NOTES.md` covering routes, 365-day repository retention, options/components, state
      volume & migration, authentication & ADC boundaries, optional editor setup, and local persistence testing.
- [x] 2.2 Run `just docs` to generate `src/gcloud-cli/README.md` and update `README.md`, translate the `gcloud-cli` row
      into `README.zh.md`, and verify `just docs-check` passes.

## 3. Automated and Persistence Tests

- [x] 3.1 Create `test/gcloud-cli/compatibility.json`, `test/gcloud-cli/test.sh`, and `test/gcloud-cli/duplicate.sh`;
      verify `just test gcloud-cli` passes across all compatibility images.
- [x] 3.2 Create `test/gcloud-cli/scenarios.json`, `test/gcloud-cli/installer.sh`, and scenario scripts
      (`test_components_apt`, `test_components_dnf`, `test_pinned_version`, `test_fallback_components`, `test_state`,
      `fail_contract`); verify `just test-scenarios gcloud-cli` passes.
- [x] 3.3 Create `test/gcloud-cli/manual/state_persistence.sh` and verify unattended two-container synthetic-fixture
      recreation and isolation pass.

## 4. Verification and Review Readiness

- [ ] 4.1 Run `just check`, `just test gcloud-cli`, `just test-scenarios gcloud-cli`, and
      `test/gcloud-cli/manual/state_persistence.sh`, complete independent code, security, and first-party source reviews
      until no valuable findings remain, verify PR CI checks pass, and record results in the PR Validation section.
