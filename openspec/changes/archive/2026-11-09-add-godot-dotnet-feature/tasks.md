# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/godot-dotnet/` and `test/godot-dotnet/` with `just new-feature godot-dotnet`; verify the
      generated `devcontainer-feature.json` carries the `version` option of the delta spec
- [x] 1.2 Write `src/godot-dotnet/devcontainer-feature.json` (version `1.0.0`, `version` proposals `["latest","4.6.3"]`,
      `dependsOn` `ghcr.io/devcontainers/features/dotnet:2` with `{"version": "lts"}` and nothing else, no
      `customizations`, `installsAfter`, `containerEnv`, lifecycle command, or privilege-widening key); verify with
      `just validate`, `just spec-check`, and by reading the file against design.md (Options, Security review)
- [x] 1.3 Write `src/godot-dotnet/install.sh` (bash) per design.md Goals: option validation with the accepted forms and
      the minimum `4.2.2`, platform gate (Debian and Ubuntu, `apt-get`), ownership of `/usr/local/bin/godot` and
      `/opt/godot-dotnet` per the outcome table, prerequisites with the fontconfig library, `latest` resolution with the
      strict tag form, skip check, checksum list before archive, exact checksum entry, archive listing check and
      extraction of the top directory, a new release directory with explicit ownership and modes, version check of the
      staged executable, the link switch by one rename, removal of the other entries, and the cleanup trap; verify with
      `shellcheck` and a build of `debian:12` with default options through `just test godot-dotnet`
- [x] 1.4 Write `src/godot-dotnet/NOTES.md` with the content the proposal's Acceptance names and regenerate
      `src/godot-dotnet/README.md` and the root `README.md` list with `just docs`; verify `just docs-check` passes

## 2. Tests

- [x] 2.1 Write `test/godot-dotnet/compatibility.json` with the two images of design.md (Supported images), both
      architectures, `scenarioArchitectures` both; verify `just validate`
- [x] 2.2 Write `test/godot-dotnet/test.sh` and its shared project helper covering Default install, SDK available to the
      remote user, SDK installed by the dependency, Dependency environment reaches the remote user, Omitted version,
      Building C# scripts headless, Running a C# project headless, Running a project headless, Importing a project
      headless, Language server headless, Minimal image, No graphical session libraries, Nothing else configured after
      install, Package-manager caches after install, and No install residue; verify `just test godot-dotnet` passes on
      every image of this machine's architecture
- [x] 2.3 Write `test/godot-dotnet/duplicate.sh` covering Different version the second time, with the guard that the
      replace path runs; verified by the same `just test godot-dotnet` run
- [x] 2.4 Write `test/godot-dotnet/scenarios.json` and the version scenarios of design.md (Decisions: Scenarios):
      `test_version_explicit` (with the C# build), `test_version_tag_form`, `test_version_two_part`; verify each with
      `just test-scenarios godot-dotnet --scenario <name>`
- [x] 2.5 Write `fail_installation.sh`, the `installer.sh` helper, and the `fixture_curl.sh` stub covering every run
      design.md (Goals) lists for `fail_installation`; verify
      `just test-scenarios godot-dotnet --scenario
      fail_installation` passes

## 3. Manual checks and documentation

- [x] 3.1 Run the manual checks design.md (Goals) lists on amd64 (the Ubuntu 18.04 version-check failure, `godot` and
      `godot-dotnet` together in both install orders, and the merged configuration of the `NOTES.md` editor example) and
      record each result in the PR's Validation section
- [x] 3.2 Add the translated `godot-dotnet` row to `README.zh.md`; verify it matches the generated row of `README.md`

## 4. Integration

- [x] 4.1 Run `just check`, `just test godot-dotnet`, and `just test-scenarios godot-dotnet`; record the results and the
      CI run in the PR's Validation section

## Workflow follow-up

- Once .NET 11 is released (scheduled for 2026-11-10; on 2026-11-09 the release metadata still lists 11.0.100-rc.3),
  re-run the Godot 4.7.2 C# build on its runtime, as design.md (Context, Risks) records for the release candidate, and
  report the result on the pull request; with `lts` the feature's own installs stay on .NET 10 either way.
