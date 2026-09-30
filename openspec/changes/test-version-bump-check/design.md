# Design

## Context

- `checkVersionBumps(model, base)` in `scripts/validate.ts` and its helpers `baseExists` and `readBaseJsonc` call git
  through `runGit` in `scripts/lib/repo.ts`, which always runs in the process's working directory. The model comes from
  `loadRepo(root)`, which already takes a root.
- The `--allow-missing-base` decision lives in the script's `import.meta.main` block, not in a function a test can call.
- `just scripts-check` runs `deno test --allow-read --allow-write=/tmp scripts/`; it runs every test file in one
  process, one test at a time.
- `loadRepo` validates each `compatibility.json` against `<root>/test/compatibility.schema.json`, so a throwaway
  repository needs that schema file.
- Verified with Deno 2.9.7 on 2026-09-30: passing `env` to `Deno.Command` for a child process needs no `--allow-env`.
- The cases come from the hand checks recorded in #3; the proposal lists them.

## Goals / Non-Goals

**Goals:**

- The version bump code takes the repository directory as a parameter that defaults to the current directory, so
  existing callers need no change, and the command line behaves as before even though its main block now calls the
  extracted missing-base function (Decisions). Checked by running `scripts/validate.ts` with `--base origin/main`, and
  with a base that does not exist both with and without `--allow-missing-base`, before and after the change: the output,
  including the skip notice, and the exit code are the same.
- The tests run the production code path, not a copy: they call the exported functions of `scripts/validate.ts` on a
  model from `loadRepo(<tmp repo>)`. Checked by the mutations in the proposal's Acceptance.
- Each test builds its own repository and removes it in a `finally`, so tests share no state and can run in any order.
  Checked by running a single test with `--filter` as well as the whole file.
- The developer's global and system git configuration cannot change a result. The helper runs its own git commands with
  `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`, and writes repository-local settings that override the
  global keys the production git calls read (`core.excludesFile`, `core.hooksPath`) and the ones its commits need
  (`user.name`, `user.email`, `commit.gpgsign`). Checked by the hostile-configuration run in the proposal's Acceptance.

**Non-Goals:**

- Changing what `checkVersionBumps` enforces or how it words a problem (the issue's Out of scope).
- Testing `checkFeatures` or the rest of `validate.ts` against real repositories; only the git-dependent version bump
  path lacks coverage.
- A shared git-repository fixture library for other scripts; the helper lives in the test file until a second user
  appears.

## Decisions

- **Thread a repository directory through instead of changing the working directory.** `runGit` gains an optional
  working directory; `baseExists`, `readBaseJsonc`, and `checkVersionBumps` gain an optional root they pass on.
  Rejected: `Deno.chdir` into each temporary repository, which is process-wide state that a future `--parallel` run or a
  failed test's missing restore would leak into every other test.
- **Extract the missing-base decision into an exported function.** The branch in `import.meta.main` that either skips
  with a notice (`--allow-missing-base` and no base) or runs `checkVersionBumps` moves into a function returning the
  problems and the notice, and the main block prints them as before. Rejected: running `scripts/validate.ts` as a
  subprocess, which needs `--allow-run` for the Deno binary, a fully valid feature tree so `checkFeatures` reports
  nothing else, and parsing stderr to find the one message under test.
- **A new test file for the git-backed tests** (`scripts/validate_test.ts`), separate from the pure tests in
  `scripts/checks_test.ts`, so the pure tests stay readable and the git fixtures stay next to the tests that use them.
- **Minimal fixtures.** Each repository holds only `test/compatibility.schema.json` (copied from the checkout) and the
  one or two features a case needs, with a `devcontainer-feature.json` and a `compatibility.json`; `loadRepo` needs
  nothing else, and `checkFeatures` is not called.
- **Missing merge base built from an unrelated history.** The base is a commit on an orphan branch, which gives the same
  `git merge-base` failure a shallow clone does without depending on clone depth.

## Risks / Trade-offs

- [Git versions differ between the dev container and the CI runner] → The helper uses only long-stable commands
  (`init -b`, `commit`, `checkout -b`, `checkout --orphan`); the CI `scripts` job on this PR shows the runner's git
  passes.
- [Tests get slower as each one spawns git several times] → A handful of small repositories under `/tmp`; if
  `just scripts-check` grows noticeably, cases share one base repository per test with separate branches.
- [A test that fails midway leaves a directory under `/tmp`] → Removal runs in `finally`; a crash of the whole process
  can still leave one, which `/tmp` cleanup handles.
