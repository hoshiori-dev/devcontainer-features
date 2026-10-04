# Tasks

## 1. Scenario configuration and planning

- [x] 1.1 Add the optional scenario architecture schema and shared default accessor; verify valid and invalid
      declarations in unit tests.
- [x] 1.2 Expand scenario matrix entries with architecture and runner, and declare glab's existing dual-architecture
      coverage; verify default, explicit, empty, no-scenario, and matrix-limit cases in unit tests.
- [x] 1.3 Update the shared workflow and remove the dedicated job; synchronize workflow and affected-script descriptions
      and the CI job map, and verify the planned jobs with `just affected`.

## 2. Scenario compatibility validation

- [x] 2.1 Check owner and referenced in-repo feature images on each selected architecture, retaining global amd64 checks
      and build exemptions; verify architecture-specific failures and exemptions in unit tests.
- [x] 2.2 Document the configuration and validation rules in the testing guide; verify documentation against the schema,
      planner, and workflow.

## 3. Integration verification

- [x] 3.1 Run `just check` with the CI-pinned OpenSpec version and review the diff; verify unchanged supported pairs,
      feature artifacts, and required-check settings.
- [x] 3.2 Push the implementation, verify all eight glab scenarios on both native architectures and the remaining CI
      checks, and record every proposal Acceptance item with results and run links in the PR's Validation section before
      marking ready.
