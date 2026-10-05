# Tasks

## 1. Error handling

- [ ] 1.1 `scripts/validate.ts`: `isExecutable` catches only NotFound; `readBaseJsonc` treats only a path missing from
      the base commit as a new feature and fails on other git errors and on base metadata that is not valid JSONC; the
      compatibility skip condition gets a named boolean; verify with tests in `scripts/validate_test.ts` that make each
      read fail with an error other than NotFound
- [ ] 1.2 `scripts/check_openspec.ts` (lstat), `scripts/docs.ts`, and `scripts/tag_releases.ts` surface unexpected
      errors, and `tag_releases.ts` fails on unreadable metadata or a missing version; `scripts/test_feature.ts` reports
      a failed container or staging cleanup on stderr; verify with tests where the code is testable and by reading the
      changed paths otherwise

## 2. Release hardening and telemetry

- [ ] 2.1 `setup-tools` gains a `just` input (default `"true"`), `publish` passes `"false"`, the `PATH` change gets its
      own named step with a comment, and every read-only job checks out with `persist-credentials: false`; verify by
      reading each workflow and by CI on the PR
- [ ] 2.2 Every place the tooling runs OpenSpec sets `OPENSPEC_TELEMETRY=0`, and `--allow-net=edge.openspec.dev` and
      `--allow-env=LOG_TOKENS,LOG_STREAM` carry comments giving their reasons; verify with `git grep` that no OpenSpec
      invocation lacks the variable

## 3. Documentation and tests

- [ ] 3.1 Fix the `pr-checklist` row of `.agents/knowledge/github/checks.md`; verify against `.github/workflows/pr.yml`
- [ ] 3.2 Rewrite the scenario-owner test in `scripts/checks_test.ts` with `repoWith()` and a synthetic feature; verify
      `deno test` passes

## 4. Readability

- [ ] 4.1 Split `checkFeatures` in `validate.ts` into per-concern helpers called in the same order, extract
      `generatedProblems()` in `check_openspec.ts`, and inline `exitCode` with its tests rewritten; verify that
      `scripts/validate.ts` and `scripts/check_openspec.ts` print the same output and exit code on the repository before
      and after
- [ ] 4.2 Bring every line in `scripts/`, the `justfile`, and the workflows within 120 characters (URL-only lines
      excepted), and restyle shell in workflows and composite actions to the shell style guide; verify with a
      line-length scan and `deno fmt --check`

## 5. POSIX scaffold

- [ ] 5.1 After #69 merges and this branch is rebased onto it, add `--posix` to `scripts/new_feature.ts` with tests in
      `scripts/checks_test.ts`; verify a scaffolded POSIX feature passes shellcheck with `require-variable-braces` and
      `--shell=sh`

## 6. Integration

- [ ] 6.1 Run `just check` and confirm it passes and CI on the PR is green; record the results in the PR's Validation
      section
