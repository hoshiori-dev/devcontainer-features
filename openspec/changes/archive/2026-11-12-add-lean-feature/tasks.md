# Tasks

## 1. Scaffold

- [x] 1.1 Scaffold `lean` with `just new-feature lean` at version 1.0.0, with the options `elanVersion`,
      `defaultToolchain`, and `preinstallToolchains`, their proposals and descriptions from design.md (Option
      interface), the `containerEnv`, `mounts`, `onCreateCommand`, `installsAfter`, and VS Code customizations the
      proposal's Impact names, and the compatibility list from design.md (Supported images); verify `just validate` and
      `just spec-check` accept it.

## 2. Installer and its tests

- [x] 2.1 Implement `install.sh`: option validation (elan release form and minimum, toolchain names, the
      `preinstallToolchains` list), the platform gate (architecture, glibc, family, package manager), the remote user
      and group checks, the target checks, missing prerequisites in one transaction with cache cleanup, `latest` from
      the redirect, the skip check, the archive download with GitHub's digest when reported, staging and renames of elan
      and the six proxies, the group and the mount point, the creation script and the default-toolchain file, and the
      `trap`; verify shellcheck passes through `just check`.
- [x] 2.2 Implement build-time toolchains in `install.sh`: a temporary `ELAN_HOME` beside `/usr/local/share/lean/` that
      links the image's toolchains, `elan toolchain install` per name, renames into `toolchains/`, removal of group and
      other write, and cleanup on failure; verify with a local build that a listed toolchain lands root-owned in
      `/usr/local/share/lean/toolchains/` and a repeated name downloads nothing.
- [x] 2.3 Implement the creation script (`initialize`): the fit check, the repair through `sudo -n chown -R -h -P`, the
      volume's directories, the links to build-time toolchains with dangling-link removal, `elan default` from the
      default-toolchain file, and warnings that let the creation continue; verify shellcheck passes and the script exits
      0 on every path.
- [x] 2.4 Write `test.sh` (defaults) and `duplicate.sh` (`4.1.0`, `leanprover/lean4:v4.35.0` for both toolchain options,
      then the defaults) with the checks design.md (Tests) lists; verify `just test lean` passes on this machine's
      architecture.
- [x] 2.5 Add the scenarios `test_offline_toolchains`, `test_version_floor`, `test_unmanaged_default`,
      `test_changed_uid` (with its Dockerfile), and `test_repair_volume` from design.md (Tests), with
      `scenarioArchitectures` `["amd64","arm64"]`; verify each with `just test-scenarios lean --scenario <name>`.
- [x] 2.6 Add the fixture scenario `fail_contract` with its recording `curl`, `uname`, and API stand-ins, covering every
      case design.md (Tests) lists for it; verify `just test-scenarios lean --scenario fail_contract` passes and that
      each case asserts a non-zero exit, its message, and unchanged targets, packages, and temporary directory.

## 3. Documentation and manual checks

- [x] 3.1 Write `NOTES.md` covering every topic of the spec's "Lean usage guidance" requirement; verify each command and
      setting it shows against the spec.
- [x] 3.2 Check by hand, once, on this machine's architecture: a rebuild (`devcontainer up` with
      `--remove-existing-container`) keeps a run-time toolchain and cache files, two workspaces get two volumes, and VS
      Code requests the extension; record the results for the PR's Validation section.
- [x] 3.3 Regenerate READMEs with `just docs`, and translate the root feature-list addition into `README.zh.md`; verify
      `just docs-check`.

## 4. Integration

- [x] 4.1 Run `just check`, `just test lean`, and `just test-scenarios lean`, review the diff against the approved
      specification and design, and resolve findings.
- [x] 4.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
