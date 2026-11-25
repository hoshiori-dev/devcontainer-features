# Tasks

## 1. Scaffold

- [x] 1.1 Scaffold `packer` with `just new-feature packer --posix` at version 1.0.0, with the `version` option and its
      proposals and description from design.md, no other metadata, and the compatibility list from design.md (Supported
      images); verify `just validate` and `just spec-check` accept it.

## 2. Installer and its tests

- [x] 2.1 Implement `install.sh`: option validation, the platform gate, the target check, prerequisites in one
      transaction with cache cleanup, `latest` resolution from the Checkpoint answer, the skip check with `HOME` in the
      temporary directory and `CHECKPOINT_DISABLE=1`, key and signature download without redirects, signature
      verification against the pinned fingerprint, the archive checksum, extraction of `packer` only, staging and the
      rename, and the `trap`; write the `checks.sh`-based `test.sh` with the checks design.md (Tests) lists, and
      `duplicate.sh` (`1.15.4`, then the defaults); verify `just test packer` passes.
- [x] 2.2 Add the real-release scenarios `test_version_floor` and `test_version_explicit` from design.md (Tests), with
      `scenarioArchitectures` `["amd64","arm64"]`; verify each with `just test-scenarios packer --scenario <name>`.
- [x] 2.3 Add the fixture scenario `fail_contract` with its recording `curl` stand-in, `uname` stand-in, and fixtures,
      covering every case design.md (Tests) lists for it; verify `just test-scenarios packer --scenario fail_contract`
      passes and that each case asserts a non-zero exit, its message, and unchanged target, packages, and temporary
      directory.

## 3. Documentation

- [x] 3.1 Write `NOTES.md` with every item the proposal's Acceptance lists for it (how `latest` is chosen and pinning,
      plugins and `packer init`, keeping plugins and downloads across rebuilds, the Checkpoint service, the other
      `/usr/sbin/packer`, shell completion, the license) and the compatibility list; verify every command and setting it
      shows by running it in a container built with the feature.
- [x] 3.2 Regenerate READMEs with `just docs`, translate the root feature-list addition into `README.zh.md`; verify
      `just docs-check`.

## 4. Integration

- [x] 4.1 Run `just check`, `just test packer`, and `just test-scenarios packer`, review the diff against the approved
      specification and design, and resolve findings.
- [ ] 4.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
