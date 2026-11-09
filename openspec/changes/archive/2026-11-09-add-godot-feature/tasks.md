# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/godot/` and `test/godot/` with `just new-feature godot`; verify the generated
      `devcontainer-feature.json` carries the `version` option of the delta spec
- [x] 1.2 Write `src/godot/devcontainer-feature.json` (version `1.0.0`, `version` proposals `["latest","4.6.3"]`, no
      `customizations`, `dependsOn`, `installsAfter`, `containerEnv`, lifecycle command, or privilege-widening key);
      verify with `just validate`, `just spec-check`, and by reading the file against design.md (Options, Security
      review)
- [x] 1.3 Write `src/godot/install.sh` (bash) per design.md Goals: option validation with the accepted forms, platform
      gate, target check, prerequisites with the fontconfig library, `latest` resolution with the strict tag form, skip
      check, checksum list before archive, exact checksum entry, archive listing and single-entry extraction, version
      check of the staged executable, atomic rename, cleanup trap; verify with `shellcheck` and a build of `debian:12`
      with default options through `just test godot`
- [x] 1.4 Write `src/godot/NOTES.md` (headless scope and what a display needs, the Godot Tools extension and its
      headless language server in the user's own configuration with what they run, pinning `version` to the project's
      release, export templates from the same release verified against `SHA512-SUMS.txt` and where Godot looks for them,
      no .NET build or pre-releases, what the install does, OS support) and regenerate `src/godot/README.md` and the
      root `README.md` list with `just docs`; verify `just docs-check` passes
- [x] 1.5 Apply the package revision `1d69cbd` (minimum `4.2.2`): compare the patch in `install.sh`'s minimum check,
      raise the minimum in the `version` description and `NOTES.md`, and add `4.2`, `4.2.1`, the `latest` tag
      `4.2.1-stable`, and the minimum `4.2.2` itself to `fail_installation`; verify with `just docs-check` and
      `just test-scenarios godot --scenario fail_installation`

## 2. Tests

- [x] 2.1 Write `test/godot/compatibility.json` with the three images of design.md (Supported images), both
      architectures, `scenarioArchitectures` both; verify `just validate`
- [x] 2.2 Write `test/godot/test.sh` and its shared project helper covering Default install, Omitted version, Running a
      project headless, Importing a project headless, Language server headless, Minimal image, No graphical session
      libraries, Nothing else configured after install, Package-manager caches after install, and No install residue;
      verify `just test godot` passes on every image of this machine's architecture
- [x] 2.3 Write `test/godot/duplicate.sh` covering Different version the second time, with the guard that the replace
      path runs; verified by the same `just test godot` run
- [x] 2.4 Write `test/godot/scenarios.json` and the version scenarios of design.md (Decisions: Scenarios):
      `test_version_explicit`, `test_version_tag_form`, `test_version_two_part`; verify each with
      `just test-scenarios godot --scenario <name>`
- [x] 2.5 Write `fail_installation.sh`, the `installer.sh` helper, and the `fixture_curl.sh` stub covering every run
      design.md (Goals) lists for `fail_installation`, with the `apt-get` stub and the absent fontconfig library for the
      runs that must fail before any change; verify `just test-scenarios godot --scenario fail_installation` passes

## 3. Manual checks and documentation

- [x] 3.1 Run the manual checks design.md (Goals) lists on amd64 (the Ubuntu 18.04 version-check failure and the
      `NOTES.md` editor example), and record each result in the PR's Validation section
- [x] 3.2 Add the translated `godot` row to `README.zh.md`; verify it matches the generated row of `README.md`

## 4. Integration

- [x] 4.1 Run `just check`, `just test godot`, and `just test-scenarios godot`; record the results and the CI run in the
      PR's Validation section
