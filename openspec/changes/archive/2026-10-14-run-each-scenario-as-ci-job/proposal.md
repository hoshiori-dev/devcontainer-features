# Proposal

## Why

A feature's scenarios currently run sequentially within each architecture's CI job, so feedback waits for their combined
runtime and a failed scenario is hidden behind a feature-level job name. This change implements
[issue #118](https://github.com/hoshiori-dev/devcontainer-features/issues/118).

## What Changes

- Affected feature scenarios run in separate CI jobs on each declared scenario architecture, with the feature, exact
  scenario name, and architecture visible in the job list.
- Developers can reproduce a single scenario job with `just test-scenarios <id> --scenario <name>`; omitting the option
  continues to run all of the feature's scenarios.
- Invalid scenario selections fail clearly before starting Docker rather than succeeding with no tests.
- The testing guide and CI job map describe the new job granularity and local command.
- CI measurements compare the existing sequential jobs with the separate scenario jobs and assess runner queuing and
  repeated setup cost before the change is marked ready.

## Capabilities

### New Capabilities

None. This is a harness change with `skip_specs: true`.

### Modified Capabilities

None. Feature installation contracts do not change.

## Impact

- Expected implementation scope: `scripts/lib/repo.ts`, `scripts/lib/repo_test.ts`, `scripts/lib/stage.ts`,
  `scripts/lib/stage_test.ts`, `scripts/test_feature.ts`, its argument-validation tests, `scripts/affected.ts`,
  `.github/actions/feature-test/action.yml`, `.github/workflows/ci.yml`, `scripts/checks_test.ts`, the `justfile` recipe
  comment, `.agents/knowledge/testing.md`, and `.agents/knowledge/github/checks.md`.
- No feature id's published files, scenario definitions, supported image/architecture pairs, or specifications change;
  no feature needs a version bump. `dnf-packages` and `glab` provide existing CI measurement and selection cases.
- No new runtime, package dependency, required check, workflow permission, release change, or repository setting.
- Check the `CONTRIBUTING.md` overview when updating the testing guide; revise it only if the overview becomes stale.

## Acceptance

**Becomes true:**

- Every affected feature scenario has exactly one matrix entry per declared scenario architecture; each entry names the
  feature, scenario, architecture, and native runner. The job list identifies a failed scenario directly.
- Each scenario job executes only its named scenario, including when another name contains that name as a substring. The
  staged configuration retains the selected scenario's full configuration and rewrites its in-repo references.
- `just test-scenarios glab --scenario test_version_explicit` runs only that scenario, excluding
  `test_version_explicit_alpine`. Omitting `--scenario` still runs every glab scenario on the host architecture.
- An unknown or empty scenario name, an unknown feature, or `--scenario` in default/global mode fails with an actionable
  error before a registry container or staging directory is created.
- Planner, staging, argument-validation, and workflow-wiring regression checks pass, including empty selections,
  features without scenarios, multiple architectures, exact selection, and the 256/257-entry boundary. `just check`
  passes after implementation.
- A draft PR records linked before/after CI runs for `dnf-packages` and `glab`: job count, longest scenario-job
  duration, first-start-to-last-finish span, queuing, setup duration, and summed job durations. Every new job runs one
  scenario; the comparison demonstrates shorter individual jobs and evaluates whether queuing offsets the elapsed-time
  gain.
- Testing documentation and the job map match the final matrix and local command.

**Stays true:**

- Affected-feature propagation, canary selection, compatibility-image jobs, global scenarios, and declared scenario
  architecture coverage remain unchanged. Empty selections and features without scenarios add no scenario jobs.
- Scenario contents, feature artifacts, versions, dependencies, and supported platforms remain unchanged.
- In-repo features resolve to the same checkout through the local registry, including dependency closure and the
  unrewritten installer copies used by existing scenarios.
- Each matrix retains the 256-entry limit and fails planning with a clear split-the-PR message above it.
- `ci-gate` remains the required CI entry point and fails for failed or cancelled scenario jobs; required-check settings
  and release behavior remain unchanged.
