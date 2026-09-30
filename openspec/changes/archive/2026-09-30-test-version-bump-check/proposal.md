# Proposal

Implements [#3](https://github.com/hoshiori-dev/devcontainer-features/issues/3).

## Why

`checkVersionBumps` in `scripts/validate.ts` decides whether a feature change carries the version it needs, and the
Release workflow's `verify` job runs it before every publish. Only its pure helper `compatBumpProblems` has unit tests;
the parts that ask git what changed — the merge base, uncommitted and untracked files, a missing base — were checked by
hand once during #1 and would regress unnoticed.

## What Changes

- `just scripts-check` runs Deno tests that build throwaway git repositories under `/tmp` and exercise the version bump
  check end to end, one test per case below:
  - a change under `src/<id>/` without a version bump, and the same change with one;
  - an uncommitted change to a tracked file, and an untracked new file, under `src/<id>/`;
  - a base and `HEAD` that share no merge base;
  - a base ref that does not exist, with and without `--allow-missing-base`;
  - a branch behind `main` whose compatibility list `main` extended after the branch point, and a branch whose bump
    exceeds its branch point's version but not `main`'s tip;
  - images added or dropped in `test/<id>/compatibility.json` without the bump they need, and with it.
- The `deno test` call in the `scripts-check` recipe gains `--allow-run=git`.
- The version bump code in `scripts/validate.ts` and `runGit` in `scripts/lib/repo.ts` can run against a repository
  other than the current directory, so the tests need not change the process's working directory; what the check
  enforces does not change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `scripts/validate.ts`, `scripts/lib/repo.ts`, a new test file under `scripts/`, `justfile` (`scripts-check`).
- Feature ids touched: none, so no version bump. `scripts/lib/` is test infrastructure, so CI selects the canary set,
  which is empty while no feature exists.
- CI: the `scripts` job runs the new tests through `just scripts-check`; the job ↔ command map in
  `.agents/knowledge/github/checks.md` already describes that recipe as "deno check, lint, test" and needs no edit.

## Acceptance

**Becomes true:**

- `just scripts-check` runs a test for each case listed under What Changes, and all pass.
- Measuring the changes from the base tip instead of the merge base in `checkVersionBumps` makes at least one test fail;
  so does dropping the untracked-file listing. Both mutations are made locally, observed, and reverted.
- The tests pass when the developer's global git configuration would otherwise interfere: run with `GIT_CONFIG_GLOBAL`
  pointing to a file that sets `commit.gpgsign = true` and a `core.excludesFile` that ignores every file, and with no
  `user.name` or `user.email`.

**Stays true:**

- `checkVersionBumps` reports the same problems, with the same messages, for the same repository states; `just validate`
  and the Release workflow's `verify` step behave as before.
- The tests write only under `/tmp`, remove what they create, need no network beyond the imports Deno already caches,
  and never touch the checkout they run from.
- `just check` passes, and every required check passes on this PR.
