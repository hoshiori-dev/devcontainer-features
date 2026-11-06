# Tasks

## 1. Installation contract

- [x] 1.1 Scaffold `blender` at version 1.0.0 with its sole `version` option, no customizations, and the amd64
      compatibility list from design.md; verify `just validate` and `just spec-check` accept the metadata.
- [x] 1.2 Implement platform checks, option validation, listing-based release resolution, redirect-free verified
      downloads, runtime libraries, the managed `/opt/blender` tree with its executable link, bytecode precompilation,
      conflicts, repeat installation, and staged replacement with rollback in `install.sh`; cover default installation,
      headless rendering with each engine, script status, non-root use, the executable link, the unchanged tree, and
      upstream defaults in `test.sh`, and a series installation followed by the defaults in `duplicate.sh`.
- [x] 1.3 Add scenarios with local fixtures for version validation, numeric and checksum-aware resolution, an unreleased
      series, listing, transport, redirect, and checksum failures, unsupported platforms, conflicts, the same release
      without a download, repairs, and failed replacement, plus real-release scenarios for a series and the 4.2 floor;
      verify each scenario passes with `just test-scenarios blender --scenario <name>`.

## 2. Extension development and documentation

- [x] 2.1 Write `NOTES.md` covering the topics of the Usage guidance requirement and design.md; add an offline
      (`--network=none`) scenario that runs the notes' extension and headless examples as written, including a script
      that raises and an extension that cannot load.
- [x] 2.2 Regenerate READMEs with `just docs`, translate the root feature-list addition in `README.zh.md`, and verify
      `just docs-check`.

## 3. Integration

- [x] 3.1 Run `just check`, `just test blender`, and `just test-scenarios blender`, review the diff against the approved
      specification, and resolve findings.
- [x] 3.2 Record each Acceptance item and scenario with its evidence and the CI run in the PR's Validation section;
      verify every item names its evidence.
