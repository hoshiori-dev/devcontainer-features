# Tasks

## 1. Cleanup recipe

- [x] 1.1 Add `test-clean` to the `justfile` next to the other test recipes: refuse with a non-zero exit and a reason
      while a `devcontainer features test` process runs (a `pgrep -f` pattern that cannot match the recipe's own shell),
      otherwise `docker rm -f` every container from `docker ps -aq --filter label=devcontainer.is_test_run=true` and
      report how many were removed; verify `just --list` shows it and `just lint` passes.
- [x] 1.2 Verify the recipe's behavior: with no test container it succeeds and reports none removed; during a running
      `just test-scenarios <id>` it refuses and removes nothing; after a `--preserve` run it removes that run's
      containers, `docker ps -a --filter label=devcontainer.is_test_run=true` lists none, and an unlabeled container
      running beside them survives.
- [x] 1.3 Add the recipe to the Validation table in `AGENTS.md`; verify the row names the recipe and when to run it.

## 2. Testing guide and CI path

- [x] 2.1 In `.agents/knowledge/testing.md`, Running tests locally: replace the claim that every CI job can be
      reproduced without limits by the conflict, its cause in one sentence (CLI 0.89.0's end-of-run sweep by label), the
      rule (one run per daemon, or a concurrent set all with `--preserve` then `just test-clean` after the set's last
      run, by the agent that orchestrates the set), the 137 symptom of a missed `--preserve`, the memory cost of kept
      containers, and that the sweep also removes containers kept for debugging; verify by reading the section against
      the proposal's Acceptance.
- [x] 2.2 In `testing.md`, state that feasibility testing while a change is written stays local, that the CI run of a
      reviewed push is the encouraged full quality test (most of all with several branches in flight), that container
      tests run only on pull requests so a branch without one gets none, and point to `checks.md`, Reading a run; verify
      the wording does not discourage local testing.
- [x] 2.3 In `.agents/knowledge/github/checks.md`, make the `--preserve` line of Reading a run point to the rule in
      `testing.md`; verify no rule is restated in both files.
- [x] 2.4 In `.agents/skills/github-project-workflow/SKILL.md`, Finish: name the CI path's order — publish gate review,
      push, then watch the Actions run and read its result as evidence — pointing to `testing.md` and `checks.md`;
      verify the skill restates neither file.
- [x] 2.5 Check `CONTRIBUTING.md`'s testing overview against the new rules and revise it only if it became stale; verify
      by reading it.

## 3. Integration

- [x] 3.1 Run `just check` and record the results, with the recipe checks of 1.2, in the PR's Validation section.
