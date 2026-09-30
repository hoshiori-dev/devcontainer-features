# Tasks

## 1. Repository directory parameter

- [ ] 1.1 Give `runGit` in `scripts/lib/repo.ts` an optional working directory, and `baseExists`, `readBaseJsonc`, and
      `checkVersionBumps` in `scripts/validate.ts` an optional root they pass on, defaulting to the current directory;
      verify `just scripts-check` passes and no existing caller changes
- [ ] 1.2 Move the missing-base branch of `import.meta.main` in `scripts/validate.ts` into an exported function that
      returns the problems and the skip notice, and have the main block print them as before; verify
      `scripts/validate.ts` with `--base origin/main`, and with a base that does not exist with and without
      `--allow-missing-base` (plain and with `GITHUB_ACTIONS=true`), prints the same output and exit code as before the
      change

## 2. Tests

- [ ] 2.1 Add `scripts/validate_test.ts` with a helper that builds a throwaway repository under `/tmp` (the checkout's
      `test/compatibility.schema.json`, the features a case needs, isolated git configuration per the design) and
      removes it in `finally`, plus one test per case listed in the proposal's What Changes; add `--allow-run=git` to
      the `deno test` call of the `scripts-check` recipe; verify `just scripts-check` passes and a single test passes
      alone with `--filter`
- [ ] 2.2 Mutate `checkVersionBumps` locally to measure changes from the base tip instead of the merge base, then to
      drop the untracked-file listing; verify at least one test fails for each, and revert both
- [ ] 2.3 Run the tests with `GIT_CONFIG_GLOBAL` pointing to a file that sets `commit.gpgsign = true`, a
      `core.excludesFile` ignoring every file, and no `user.name` or `user.email`; verify they pass

## 3. Integration

- [ ] 3.1 Run `just check`, push, and confirm every required check passes on this PR; record each Acceptance item of
      proposal.md with its result in the PR's Validation section
