# Tasks

## 1. Scaffold

- [ ] 1.1 Scaffold `opentofu` with `just new-feature opentofu --posix` at version 1.0.0, with the `version` option and
      its proposals and description from design.md, the `opentofu.vscode-opentofu` extension, no other metadata, and the
      compatibility list from design.md (Supported images); verify `just validate` and `just spec-check` accept it.

## 2. Installer and its tests

- [ ] 2.1 Implement `install.sh`: option validation, the platform gate, the target check, prerequisites in one
      transaction with cache cleanup, `latest` resolution from the latest-release link, the skip check with `HOME` in
      the temporary directory, key and signature download, signature verification against the pinned fingerprint, the
      archive checksum, extraction of `tofu` only, staging and the rename, and the `trap`; write the `checks.sh`-based
      `test.sh` with the checks design.md (Tests) lists, and `duplicate.sh` (`1.12.12`, then the defaults); verify
      `just test opentofu` passes.
- [ ] 2.2 Add the real-release scenarios `test_version_floor` and `test_version_explicit` from design.md (Tests), with
      `scenarioArchitectures` `["amd64","arm64"]`; verify each with `just test-scenarios opentofu --scenario <name>`.
- [ ] 2.3 Add the fixture scenario `fail_contract` with its recording `curl` stand-in, `uname` stand-in, and fixtures,
      covering every case design.md (Tests) lists for it; verify `just test-scenarios opentofu --scenario fail_contract`
      passes and that each case asserts a non-zero exit, its message, and unchanged target, packages, and temporary
      directory.
- [ ] 2.4 Check by hand once the package-manager branch of `fedora:44`, `almalinux:9`, `opensuse/leap:16.0`, and
      `archlinux:latest` with `tar` removed without its dependents, as design.md (Tests) describes; verify `install.sh`
      installs `tar`, succeeds, and leaves the cache clean, and record the result for the PR's Validation section.

## 3. Documentation

- [ ] 3.1 Write `NOTES.md`: what is installed and verified, how `latest` is chosen and how to pin `version`, excluding
      the editor extension, git for `git::` module sources, setting up a provider plugin cache and shell completion
      yourself, a distribution's `/usr/bin/tofu`, and the compatibility list; verify every command and setting it shows
      against the spec.
- [ ] 3.2 Regenerate READMEs with `just docs`, translate the root feature-list addition into `README.zh.md`; verify
      `just docs-check`.

## 4. Integration

- [ ] 4.1 Run `just check`, `just test opentofu`, and `just test-scenarios opentofu`, review the diff against the
      approved specification and design, and resolve findings.
- [ ] 4.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
