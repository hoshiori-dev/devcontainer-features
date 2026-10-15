# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/betterleaks/` and `test/betterleaks/` with `just new-feature betterleaks --posix`; verify the
      generated `devcontainer-feature.json` carries the `version` option of the delta spec and `just spec-check` (with
      the OpenSpec version CI pins) accepts it
- [x] 1.2 Write `src/betterleaks/devcontainer-feature.json` (version `1.0.0`, `proposals` `["latest","1.0.1"]`, no
      `containerEnv`, `dependsOn`, `installsAfter`, lifecycle command, or privilege-widening key); verify with
      `just validate` and by reading the file against design.md (Options, Security review)
- [x] 1.3 Write `src/betterleaks/install.sh` (POSIX sh) per design.md Goals: option validation including `-rc.N`,
      platform detection, prerequisites, `latest` resolution, skip check, checksum verification, atomic install, cleanup
      trap; verify with `shellcheck` and a build of `debian:12` with default options through `just test`
- [x] 1.4 Write `src/betterleaks/NOTES.md` (versions and pre-releases, what the install does, the unverified Sigstore
      signature, OS support) and regenerate `src/betterleaks/README.md` and the root `README.md` list with `just docs`;
      verify `just docs-check` passes

## 2. Tests

- [x] 2.1 Write `test/betterleaks/compatibility.json` with the four images of design.md (Supported images), both
      architectures, `scenarioArchitectures` both; verify `just validate`
- [x] 2.2 Write `test/betterleaks/checks.sh` and `test.sh` covering the Default install, Scan of a repository, Omitted
      version, Nothing configured after install, Package-manager caches after install, and No install residue scenarios;
      verify `just test betterleaks` passes on every image of this machine's architecture
- [x] 2.3 Write `test/betterleaks/duplicate.sh` covering Same options twice is not the path (guard), Different version
      the second time, and No install residue; verified by the same `just test betterleaks` run
- [x] 2.4 Write `test/betterleaks/scenarios.json` and the four scenario scripts of design.md (Decisions: version
      scenarios); verify `just test-scenarios betterleaks` passes

## 3. Manual checks and documentation

- [x] 3.1 Run the manual checks design.md (Goals) lists on amd64 in throwaway containers and record each result in the
      PR's Validation section
- [x] 3.2 Add the translated `betterleaks` row to `README.zh.md`; verify it matches the generated row of `README.md`

## 4. Integration

- [x] 4.1 Run `just check`, `just test betterleaks`, and `just test-scenarios betterleaks`; record the results and the
      CI run in the PR's Validation section
