# Proposal

## Why

Concurrent local container tests on one Docker daemon remove each other's containers: at the end of every
`devcontainer features test` run without `--preserve-test-containers`, the devcontainer CLI removes every container
labeled `devcontainer.is_test_run=true`, whichever run started it. Agents working on several branches at once lost
random scenarios with exit status 137, and the harness says nothing about the limit; it also never tells agents that the
full quality test of a pushed change is CI's job. This change implements
[issue #141](https://github.com/hoshiori-dev/devcontainer-features/issues/141).

## What Changes

- The testing guide states the conflict, its cause, and the rule: one local test run at a time per Docker daemon, or a
  concurrent set in which every run passes `--preserve`, followed by one cleanup once the whole set has finished.
- A new `just` recipe performs that cleanup: it removes every test container on the daemon, the same sweep the CLI makes
  at the end of a run, and refuses while a `devcontainer features test` process is still running.
- The harness keeps feasibility testing local while a change is written, and encourages the CI run as the full quality
  test of a pushed change, most of all when several branches are worked on at once, together with how to read that run.
- The `github-project-workflow` skill's Finish step names the order for the CI path: the publish gate's review, then the
  push, then watching the Actions run and reading its result.

## Capabilities

### New Capabilities

None. This is a harness change with `skip_specs: true`.

### Modified Capabilities

None. No feature's installation contract changes.

## Impact

- Expected scope: `justfile`, `.agents/knowledge/testing.md`, `.agents/knowledge/github/checks.md`,
  `.agents/skills/github-project-workflow/SKILL.md`, and the Validation table in `AGENTS.md`. `CONTRIBUTING.md` is
  checked against its overview of testing and revised only if it becomes stale.
- No feature id changes; no feature needs a version bump.
- No change to the workflows, their triggers, the required checks, `scripts/test_feature.ts`, or the devcontainer CLI.
  No new runtime or dependency.

## Acceptance

**Becomes true:**

- `testing.md`, where an agent reads before running container tests, states that concurrent `just test`,
  `just test-scenarios`, and `just test-global` runs on one daemon remove each other's containers, why, and the rule:
  one run at a time, or a concurrent set all with `--preserve` followed by the cleanup recipe after the last run of the
  set has finished. It names who runs the cleanup when one agent orchestrates several workers.
- The cleanup recipe exists, is listed by `just`, and appears in the Validation table of `AGENTS.md`. Run with no test
  container present, it succeeds and reports that nothing was removed. Run while a `devcontainer features test` process
  is running, it removes nothing and exits non-zero naming the reason. Run after a `--preserve` test run has finished,
  it removes that run's containers, and `docker ps -a --filter label=devcontainer.is_test_run=true` then lists none.
- The harness states that feasibility testing during the work stays local, that the CI run of a pushed change is the
  encouraged full quality test, how to read its result, and that a branch without a pull request gets no container test
  from a push.
- The skill's Finish step orders the CI path as review through the publish gate, push, then watching and reading the
  run.
- `just check` passes.

**Stays true:**

- Local testing is not discouraged: an agent still tests a change locally before pushing it, and the harness never
  suggests pushing untested work for CI to find the faults.
- Every push still passes the publish gate first; using CI never means publishing unreviewed work.
- A passing CI run stays evidence, not acceptance (`agent-authority.md`).
- `just test`, `just test-scenarios`, and `just test-global` behave as before, with and without `--preserve`; the CI
  workflows, triggers, and required checks are unchanged.
- The cleanup recipe removes only containers labeled `devcontainer.is_test_run=true`: the dev container itself, the
  registry containers of `scripts/test_feature.ts`, and every other container are untouched.
