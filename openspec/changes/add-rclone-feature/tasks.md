# Tasks

## 1. Scaffold and open question

- [x] 1.1 Resolve design.md's Open Question: in a throwaway `debian:12` container, run the verified `1.63.0` and
      `1.76.0` binaries with `version` and `completion bash|zsh|fish -`, with `HOME`, `XDG_CONFIG_HOME`,
      `XDG_CACHE_HOME`, and `RCLONE_CONFIG` in a temporary directory; record what each prints to stderr and that nothing
      is created outside that directory; verify the result is written into the PR's Validation notes and that no spec or
      design change follows from it, or raise it with the maintainer.
- [x] 1.2 Scaffold `rclone` with `just new-feature rclone --posix` at version 1.0.0, with the `version` and
      `installMountDependencies` options and their proposals and descriptions from design.md, no other metadata, and the
      compatibility list from design.md (Supported images); verify `just validate` and `just spec-check` accept it.

## 2. Installer and its tests

- [x] 2.1 Implement `install.sh`: option validation, the platform gate, target checks, prerequisites and `fuse3` in one
      transaction, version resolution from `version.txt`, the skip check, signature verification against the pinned
      fingerprint on the signed text only, the archive checksum, staging of the binary and the three completion files,
      the renames, cache cleanup, and the `trap`; write `checks.sh`-based `test.sh` with the checks design.md (Tests)
      lists, and `duplicate.sh` (`1.70.0` with mount dependencies, then the defaults); verify `just test rclone` passes.
- [x] 2.2 Add the real-release scenarios `test_version_floor`, `test_version_explicit`, and `test_mount_dependencies`
      from design.md (Tests), with `scenarioArchitectures` `["amd64","arm64"]`; verify each with
      `just test-scenarios rclone --scenario <name>`.
- [x] 2.3 Add the fixture scenario `fail_contract` with its recording `curl` stand-in, `gpg` wrapper, `uname` stand-in,
      and fixtures, covering every case design.md (Tests) lists for it; verify
      `just test-scenarios rclone --scenario fail_contract` passes and that each case asserts a non-zero exit, its
      message, and unchanged targets, packages, and temporary directory.

## 3. Documentation and mount check

- [x] 3.1 Write `NOTES.md`: what is installed and verified, `version` and pinning, the completion paths and the packages
      that activate them, `installMountDependencies` with the `runArgs` a mount needs, non-root mounts and
      `user_allow_other`, bringing an existing configuration in, `rclone selfupdate` and a distribution's
      `/usr/bin/rclone`, and the compatibility list; verify every command and setting it shows against the spec.
- [x] 3.2 Check a real `rclone mount` by hand once on amd64, as root and as `vscode`, in a dev container with the
      `runArgs` from `NOTES.md` and `installMountDependencies` enabled; verify the mounted directory lists and reads the
      source files, and record the result for the PR's Validation section.
- [x] 3.3 Regenerate READMEs with `just docs`, translate the root feature-list addition into `README.zh.md`; verify
      `just docs-check`.

## 4. Integration

- [x] 4.1 Run `just check`, `just test rclone`, and `just test-scenarios rclone`, review the diff against the approved
      specification and design, and resolve findings.
- [ ] 4.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
