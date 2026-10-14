# Tasks

## 1. Planner: one matrix entry per feature, scenario, and architecture

- [x] 1.1 Change `Plan.scenarios` in `scripts/lib/repo.ts` to `{ feature, scenario, arch, runner }`, expanding every
      affected feature's scenario names (file order) across `scenarioArchesOf` (declaration order), counted against
      `MATRIX_LIMIT`; verify with `deno test scripts/lib/repo_test.ts`.
- [x] 1.2 Extend `scripts/lib/repo_test.ts`: expansion of a multi-scenario, multi-architecture feature; features without
      scenarios and empty selections add no entries; overlapping names stay separate entries; exactly 256 entries pass
      and 257 fail with the split-the-PR message; verify the new tests pass and the old scenario-limit test is updated.
- [x] 1.3 Update the header of `scripts/affected.ts` to describe one scenario job per feature x scenario x architecture;
      verify `just affected` prints the expanded count on this branch.

## 2. Staging: select one scenario by exact key

- [x] 2.1 Add an optional `{ feature, scenario }` selection to `stage()` in `scripts/lib/stage.ts` that is validated
      against the loaded model before anything is copied and writes only the selected key into the staged owner's
      `scenarios.json` through the existing rewrite; verify with `deno test scripts/lib/stage_test.ts`.
- [x] 2.2 Extend `scripts/lib/stage_test.ts`: a selected scenario's staged file holds only that key with rewritten refs
      while the source file, other test folders, extra files, Dockerfile contexts, and `_feature` copies are untouched;
      an overlapping name is not selected; an unknown feature or scenario rejects before `out` is populated; verify the
      tests pass.

## 3. Runner: `--scenario` for `--mode scenarios`

- [x] 3.1 Add `--scenario <name>` to `scripts/test_feature.ts`, accepted only with `--mode scenarios`; export a pure
      preflight that distinguishes an absent option from an empty one, checks the feature and its scenario file, and
      matches the name exactly, naming the feature, the invalid name, and the valid names in its diagnostic; the run
      stages the selection and reports failures as `<feature> scenario <name>`; verify by running the script with an
      invalid selection and seeing it exit before any `docker` call.
- [x] 3.2 Narrow the roots of a single-scenario run to the owner plus the in-repo features that scenario installs
      (`installClosure` still adds dependencies); verify with a unit test of the exported roots function.
- [x] 3.3 Add `scripts/test_feature_test.ts` covering the preflight (absent, empty, unknown feature, unknown scenario,
      exact match among overlapping names, `--scenario` outside scenarios mode) and the roots; verify
      `just scripts-check` passes.
- [x] 3.4 Update the script header and the `just test-scenarios` recipe comment to name `--scenario`; verify
      `just test-scenarios glab --scenario test_version_explicit` runs only that scenario and `just test-scenarios glab`
      still runs every glab scenario.

## 4. Workflow wiring

- [x] 4.1 Add an optional `scenario` input to `.github/actions/feature-test/action.yml`, forwarded through the
      `SCENARIO` environment variable as a quoted array argument; name scenario jobs
      `scenarios (<feature>, <scenario>, <arch>)` in `.github/workflows/ci.yml` and pass `matrix.scenario`; update both
      headers; verify with `deno test scripts/checks_test.ts`.
- [x] 4.2 Add a workflow-wiring regression test to `scripts/checks_test.ts`: the scenario job name, the `scenario`
      input, the env/array forwarding with no expression in the `run:` line, and `ci-gate` still needing the scenario
      job; verify the test passes.

## 5. Documentation

- [x] 5.1 Update `.agents/knowledge/testing.md` (local command with `--scenario`, selection granularity in "How CI
      selects tests") and `.agents/knowledge/github/checks.md` (job name and equivalent command); confirm the
      `CONTRIBUTING.md` overview still holds; verify `just check` passes.

## 6. Integration and measurement

- [x] 6.1 Run `just check`; verify it passes on the branch.
- [x] 6.2 Push and record linked before/after CI runs for `dnf-packages` and `glab` with matched workloads: job count,
      longest scenario-job duration, first-start-to-last-finish span, queuing delay, setup duration, summed job
      durations, and confirmation that each new job's CLI ran one scenario; record the comparison and every Acceptance
      item with its result in the PR's Validation section.
