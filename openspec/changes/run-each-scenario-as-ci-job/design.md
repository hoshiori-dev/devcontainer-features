# Design

## Context

See [proposal.md](proposal.md) for motivation and acceptance.

`buildPlan` emits `{ feature, arch, runner }` for each feature with scenarios and each selected architecture. The shared
scenario job calls the feature-test action, which invokes `scripts/test_feature.ts --mode scenarios`. That script stages
the repository, publishes a dependency closure to a throwaway registry, then makes one CLI call for the entire scenario
file. `stage` already parses and rewrites that file. The CLI's `--filter` selects by substring.

At base commit `b4936cf2d160b642e910a2e3760f68f41ff0e56a`, the repository contains 200 feature scenarios, expanding to
217 scenario/architecture combinations across 14 features. Glab, colab-cli, and openspec declare two architectures.
Global scenarios contribute two scenarios in their existing separate job. Dnf-packages contains 39 scenarios. These
counts supersede the smaller workload described when issue #118 opened. Issue #50 is complete; staging already copies
unrewritten installers into `_feature`, which scenario selection must preserve.

Job metadata collected on 2026-10-13 from the 40 most recent successful pull-request CI runs gives the following
sequential baseline. Samples have different scenario revisions, so these medians describe existing cost rather than a
controlled speedup measurement. Skipped jobs and unexpanded matrix placeholders are excluded.

| Scenario job           | Samples | Median duration |
| ---------------------- | ------: | --------------: |
| dnf-packages, amd64    |       3 |         1,775 s |
| apt-packages, amd64    |      10 |           679 s |
| zypper-packages, amd64 |       4 |           957 s |

The latest dnf-packages sample is
[run 38382051713](https://github.com/hoshiori-dev/devcontainer-features/actions/runs/38382051713),
[job 115245145266](https://github.com/hoshiori-dev/devcontainer-features/actions/runs/38382051713/job/115245145266):
2,668 s from job start to finish, including 5 s before the feature-test composite action. The action includes tool
setup, staging, registry publication, and scenario execution; the exposed step metadata does not separate those costs.
That run's head, `48702a292c8e511f0114fc59872c2088d65d4acd`, contains 51 dnf-packages scenarios, compared with 39 at
this change's base; it cannot serve as the matched baseline without aligning the workload. The 40-run sample has no
executed glab scenario job. Issue #118's older glab baseline is 117 s on amd64 and 127 s on arm64; it is historical
context, not a matched comparison. New measurements must include glab on both architectures.

## Goals / Non-Goals

**Goals:**

- Carry one exact scenario name from the planner to staging, without interpreting it as a substring or a shell command.
  Check overlapping names in planner/staging tests and matrix values passed through action environment variables.
- Validate the selected feature and scenario before creating resources. Check invalid CLI combinations without Docker
  and verify that staging also refuses an unknown selection when called directly.
- Keep the selection in the temporary configuration only. Compare source files before/after staging and verify build
  contexts, installer copies, reference rewriting, and cleanup with existing tests plus selected-scenario fixtures.
- Use the shared native runner map for each architecture. Compare generic dual-architecture fixtures and glab entries.

**Non-Goals:**

- No concurrency inside `test_feature.ts` and no shared registry across jobs; existing cleanup and signal handling stay
  applicable to each process, verified by the diff and local execution.
- No new scenario-architecture configuration or global-scenario selector; compare existing coverage and global staging.
- No speculative image or layer cache; measure the existing setup path as part of the comparison.

## Decisions

### Expand the existing matrix by scenario name

`Plan.scenarios` entries become `{ feature, scenario, arch, runner }`. For each affected feature, `buildPlan` iterates
the scenario names and the architectures from `scenarioArchesOf`, producing one entry per pair. Feature ordering remains
sorted; scenario ordering follows the scenario file and architecture ordering follows the declaration. Planning counts
the fully expanded entries against `MATRIX_LIMIT`; exactly 256 is valid and 257 fails with the existing split-the-PR
guidance. The current full collection's 217 entries fit, leaving 39 entries of headroom.

The workflow names jobs `scenarios (<feature>, <scenario>, <arch>)` and passes `matrix.scenario` to a new optional
`scenario` input in the feature-test action. The action places the value in `SCENARIO` and appends a quoted
`--scenario "${SCENARIO}"` array argument. The workflow does not interpolate the scenario name into shell source.
Default and global jobs omit the input. `fail-fast: false`, runner selection, job timeout, cancellation, and `ci-gate`
dependencies retain their current behavior.

### Select by exact key while staging

`test_feature.ts` accepts optional `--scenario <name>` only with `--mode scenarios`. Argument preflight distinguishes an
absent option from an explicitly empty string, checks that the feature exists and that its scenario file is readable,
and verifies an exact name match. Diagnostics name the feature and invalid name and list valid names. Extract only the
preflight logic needed for unit tests; process startup remains in the executable script.

Staging accepts an optional feature/scenario selection. It validates that selection against its loaded model before
copying anything, then writes a scenario object containing only the selected key into the staged owner's
`scenarios.json`, using the existing reference rewrite. Other staged scenario files and the source checkout remain
unchanged. Extra files and Dockerfile contexts stay beside the selected scenario because the test directory is still
copied normally. Installer copies still come from source, not the rewritten artifact.

The roots for a single-scenario run are the owner plus the in-repo features named by that scenario; `installClosure`
continues to add transitive `dependsOn` and `installsAfter` dependencies. An all-scenarios run retains its existing root
set. This avoids repeatedly publishing features needed only by other scenarios, while selected-scenario dependency and
installer-copy tests guard completeness.

The CLI still receives `--skip-autogenerated --skip-duplicated` and no `--filter`. It discovers the singleton staged
file, so overlapping names cannot expand the selection. Errors and the final failure summary include the selected
scenario. `just test-scenarios` already forwards trailing arguments, so only its comment needs to mention the selector.

### Compare per-scenario jobs with the existing sequential execution

One scenario per job is the proposed approach because it gives a named failure and uses the existing matrix and local
command. It is subject to actual CI measurements before marking the PR ready.

Several scenarios per job reduce duplicated setup and runner demand but keep serial execution inside a shard and hide
the failed scenario from the job list. They are the fallback if measurements show unacceptable queuing or setup cost;
adopting them changes this approval package and requires renewed approval. Several CLI processes in one job amortize
checkout and tools but add process limits, resource contention, and cleanup coordination and retain one feature-level
check. Neither alternative is introduced speculatively.

For the controlled comparison, the same scenario files and feature sources must be used by the baseline sequential
runner and candidate jobs on a draft PR. Report both workload revisions when reusing an earlier run. Record per-feature
and per-architecture job counts and individual durations, the span from first scenario job start to last completion,
delay between plan completion and first/last job start, and summed durations. Hosted-runner setup and the feature-test
action are separate step durations; tool setup, registry startup, staging/publication, and CLI execution need timestamp
observations during the comparison to split the composite action's cost. Observations belong in the PR's measurement
record, not a new feature option or permanent benchmark service.

The acceptance report includes the exact one-scenario local command and confirms that each matrix job's CLI executes one
scenario. It evaluates individual-job reduction and aggregate elapsed time separately. If queuing or startup cost erases
the elapsed-time improvement, do not claim a speedup or mark the work ready; bring the measured shard alternative back
to the maintainer.

### Keep the existing documentation and review contract

Update the testing guide's local command and selection granularity, the CI job map's name and equivalent command, and
the headers in `affected.ts`, `ci.yml`, and the feature-test action. Workflow-wiring regression checks guard the
scenario input and environment/array forwarding alongside existing required-check protections. No repository ruleset
changes are needed because `ci-gate` is still the required CI check.

## Risks / Trade-offs

- Repeated setup increases total runner time even when feedback is faster. The controlled comparison records summed
  durations as well as elapsed time and identifies startup cost before deciding whether to retain the design.
- Runner quotas can serialize otherwise independent jobs. Measure start delays and peak overlapping jobs; do not
  describe independent matrix entries as proof of simultaneous execution.
- Scenario growth can exceed 256 entries. Keep the guard and boundary tests; a future need for matrix partitioning is
  outside this change and requires a separate design.
- Package-installer work changes scenario counts while this change is pending. Recount the final base/head matrices and
  use a matched workload for the before/after comparison; refresh this package if its design bounds change.
- A selected scenario may install several in-repo features or use extra build files. Selected-dependency and
  build-context fixtures verify those cases while preserving the ordinary staging path.
- The design adds no feature options, external download sources, permissions, or credentials. All published validation
  records contain only public workflow links and aggregate timing observations.
