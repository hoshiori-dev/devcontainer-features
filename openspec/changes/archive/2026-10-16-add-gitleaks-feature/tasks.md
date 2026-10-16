# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/gitleaks/` and `test/gitleaks/` with `just new-feature gitleaks --posix`; verify the generated
      `devcontainer-feature.json` carries the `version` option of the delta spec and the pinned OpenSpec validation
      accepts it
- [x] 1.2 Write `src/gitleaks/devcontainer-feature.json` (version `1.0.0`, `proposals` `["latest","8.2.0"]`, no
      `containerEnv`, `dependsOn`, `installsAfter`, lifecycle command, or privilege-widening key); verify with
      `just validate` and by reading the file against design.md (Options, Security review)
- [x] 1.3 Write `src/gitleaks/install.sh` (POSIX sh) per design.md Goals: option validation, platform detection, target
      check, prerequisites, `latest` resolution, skip check, checksum verification against
      `gitleaks_<version>_checksums.txt`, atomic install, cleanup trap; verify with `shellcheck` and a build of
      `debian:12` with default options through `just test`
- [x] 1.4 Write `src/gitleaks/NOTES.md` (maintenance mode and the `betterleaks` recommendation first, then versions,
      what the install does, OS support) and regenerate `src/gitleaks/README.md` and the root `README.md` list with
      `just docs`; verify `just docs-check` passes

## 2. Tests

- [x] 2.1 Write `test/gitleaks/compatibility.json` with the four images of design.md (Supported images), both
      architectures, `scenarioArchitectures` both; verify `just validate`
- [x] 2.2 Write `test/gitleaks/checks.sh` and `test.sh` covering the Default install, Scan of a repository, Omitted
      version, Nothing configured after install, Package-manager caches after install, and No install residue scenarios;
      verify `just test gitleaks` passes on every image of this machine's architecture
- [x] 2.3 Write `test/gitleaks/duplicate.sh` covering Different version the second time and No install residue, with the
      guard that the replace path runs; verified by the same `just test gitleaks` run
- [x] 2.4 Write `test/gitleaks/scenarios.json` and the four scenario scripts of design.md (Decisions: version
      scenarios); verify `just test-scenarios gitleaks` passes

## 3. Manual checks and documentation

- [x] 3.1 Run the manual checks design.md (Goals) lists on amd64 in throwaway containers and record each result in the
      PR's Validation section
- [x] 3.2 Add the translated `gitleaks` row to `README.zh.md`; verify it matches the generated row of `README.md`

## 4. Integration

- [x] 4.1 Run `just check` (with the pinned OpenSpec for `spec-check`), `just test gitleaks`, and
      `just test-scenarios gitleaks`; record the results and the CI run in the PR's Validation section
