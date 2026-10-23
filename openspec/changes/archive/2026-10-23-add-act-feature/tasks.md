# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/act/` and `test/act/` with `just new-feature act --posix`; verify the generated
      `devcontainer-feature.json` carries the `version` and `defaultImage` options of the delta spec
- [x] 1.2 Write `src/act/devcontainer-feature.json` (version `1.0.0`, `version` proposals `["latest","0.2.80"]`,
      `defaultImage` enum `["none","medium","large"]`, `containerEnv` `ACT_DISABLE_VERSION_CHECK=1`, `installsAfter`
      docker-in-docker and docker-outside-of-docker, no `dependsOn`, lifecycle command, or privilege-widening key);
      verify with `just validate`, `just spec-check`, and by reading the file against design.md (Options, Security
      review)
- [x] 1.3 Write `src/act/install.sh` (POSIX sh) per design.md Goals: option validation, platform detection, target and
      configuration-path checks, prerequisites, `latest` resolution, skip check, checksum verification against
      `checksums.txt`, atomic install, configuration file for `defaultImage`, cleanup trap; verify with `shellcheck` and
      a build of `debian:12` with default options through `just test act`
- [x] 1.4 Write `src/act/NOTES.md` (Docker Engine requirement with docker-in-docker and docker-outside-of-docker
      examples and why neither is a dependency, `defaultImage` and the first-run prompt, versions, what the install
      does, OS support) and regenerate `src/act/README.md` and the root `README.md` list with `just docs`; verify
      `just docs-check` passes

## 2. Tests

- [x] 2.1 Write `test/act/compatibility.json` with the four images of design.md (Supported images), both architectures,
      `scenarioArchitectures` both; verify `just validate`
- [x] 2.2 Write `test/act/checks.sh` and `test.sh` covering Default install, Listing a repository's workflows, Omitted
      version, Omitted defaultImage, Version notices off in the container, Image without Docker, Nothing else configured
      after install, Package-manager caches after install, and No install residue; verify `just test act` passes on
      every image of this machine's architecture
- [x] 2.3 Write `test/act/duplicate.sh` covering Different version the second time and Default images selected, then
      none, with the guard that the replace path runs; verified by the same `just test act` run
- [x] 2.4 Write `test/act/scenarios.json` and the scenario scripts of design.md (Decisions: Scenarios): four version
      scenarios, `test_default_image_medium` (ownership, lines, dry run without a terminal) and
      `test_default_image_large`; verify `just test-scenarios act` passes

## 3. Manual checks and documentation

- [x] 3.1 Run the manual checks design.md (Goals) lists on amd64 in throwaway containers, including running a job with
      docker-in-docker, and record each result in the PR's Validation section
- [x] 3.2 Add the translated `act` row to `README.zh.md`; verify it matches the generated row of `README.md`

## 4. Integration

- [x] 4.1 Run `just check`, `just test act`, and `just test-scenarios act`; record the results and the CI run in the
      PR's Validation section
