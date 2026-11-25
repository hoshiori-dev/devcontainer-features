# Tasks

## 1. Installation contract

- [x] 1.1 Scaffold `freecad` at version 1.0.0 with its sole `version` option, no customizations, and the amd64 and arm64
      compatibility list from design.md; verify `just validate` and `just spec-check` accept the metadata.
- [x] 1.2 Implement platform checks, option validation, release resolution through the GitHub API, asset selection,
      verified downloads, runtime libraries, unpacking, the managed `/opt/freecad` tree with its two launchers, bytecode
      precompilation, conflicts, repeat installation, and staged replacement with rollback in `install.sh`; cover the
      default installation, command-line modeling and export, exit status, the launch environment, non-root use, the
      unchanged tree, upstream defaults, and GUI use on the offscreen platform and through an X server the test starts
      in `test.sh`, and a series installation followed by the defaults in `duplicate.sh`; verify with
      `just test freecad`.
- [x] 1.3 Add a scenario with local fixtures for version validation, numeric resolution, pre-releases, a mislabeled
      latest release, metadata, asset, transport, and checksum failures, unsupported platforms, conflicts, the same
      release without a download, repairs, and failed replacement, plus real-release scenarios for a series and the
      1.1.0 floor; verify each scenario passes with `just test-scenarios freecad --scenario <name>`.

## 2. Documentation

- [x] 2.1 Write `NOTES.md` covering the topics of the Usage guidance requirement and design.md; run the notes'
      command-line and GUI examples as written in the tests, including a script that raises.
- [x] 2.2 Regenerate READMEs with `just docs`, translate the root feature-list addition in `README.zh.md`, and verify
      `just docs-check`.

## 3. Integration

- [x] 3.1 Run `just check`, `just test freecad`, and `just test-scenarios freecad`, review the diff against the approved
      specification, and resolve findings.
- [x] 3.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
