# Design

## Context

- The #52 audit (2026-10-05) reviewed `scripts/`, the `justfile`, `.github/workflows/`, `.github/actions/`, and
  `.devcontainer/setup.sh` read-only. It confirmed: no `pull_request_target`, no `${{ }}` inside `run:` blocks, actions
  pinned by SHA, top-level `permissions: contents: read`, and no secret or personal-data exposure. The dev container's
  installers are protected and tracked separately (#71).
- OpenSpec 1.13.2 sends anonymous usage events to `edge.openspec.dev` unless `OPENSPEC_TELEMETRY=0`, `DO_NOT_TRACK=1`,
  or `CI` is set (its `dist/telemetry/index.js`). CI is already silent; local runs are not.
- `scripts/tag_releases.ts` pushes tags with the job's credentials, so `publish` needs them; `base-checks` fetches the
  base commit of a public repository, which needs none.
- The maintainer chose to include the workflow shell restyle, the `validate.ts` and `check_openspec.ts` refactor, and a
  `--posix` scaffold option in this change.
- This change and #69 both edit `scripts/new_feature.ts` and `scripts/checks_test.ts`; #69 lands first and this branch
  takes it in from `main`, so the POSIX scaffold uses #69's `${NAME-default}` form.

## Goals / Non-Goals

**Goals:**

- Unexpected errors surface with the file or command they concern. Checked by unit tests that make each read fail with
  an error other than NotFound.
- Behavior on valid input is unchanged. Checked by `just check`, the existing tests, and comparing `validate.ts` and
  `check_openspec.ts` output before and after on the current repository.

**Non-Goals:**

- A dependency lockfile, `.shellcheckrc`, or changes to protected files.

## Decisions

- **Catch only NotFound.** `docs.ts`, `check_openspec.ts` (lstat), and `validate.ts` (`isExecutable`) catch
  `Deno.errors.NotFound` the way `exists()` in `scripts/lib/repo.ts` does, and rethrow anything else. `test_feature.ts`
  reports a failed `docker rm -f` or staging removal on stderr instead of discarding it, without failing a run whose
  tests passed. Rejected: leaving the broad catches with comments, which keeps the hidden recovery #52 asks to remove.
- **Release tagging fails on unreadable metadata.** `tag_releases.ts` lets a read or parse error of
  `devcontainer-feature.json` end the job with the file named, and a missing or non-string `version` becomes an error.
  `verify` has already validated the same commit, so this only fires on a state that should not exist. Rejected: keeping
  the warning, which can leave a published version untagged while the job passes.
- **Base reads in the version bump check.** `readBaseJsonc` checks first whether the path exists in the base commit
  (`git rev-parse --verify`): a missing path means a new feature; any other git error, or base metadata that is not
  valid JSONC, is a problem reported like the others. The compatibility condition gets a named boolean. Rejected:
  treating every failed `git show` as a new feature, which skips the bump check for the wrong reason; `git cat-file -e`,
  planned first, which reports a path whose object is missing the same way as a missing path (found during
  implementation).
- **Release hardening.** `setup-tools` gains a `just` input, default `"true"`; `publish` passes `"false"`. Jobs that
  only read the repository check out with `persist-credentials: false`. `publish` keeps its credentials for the tag
  push. Rejected: moving checkout after tool installation in `publish` (the composite action lives in the checkout);
  pushing tags with an explicit token header (more moving parts for the same exposure).
- **Telemetry off.** `OPENSPEC_TELEMETRY=0` joins `OPENSPEC_NO_UPDATE_CHECK=1` in every `Deno.Command` env in
  `check_openspec.ts` and in the `justfile` recipe that runs OpenSpec. `--allow-net=edge.openspec.dev` stays, so an
  interactive Deno does not stop at a permission prompt, with a comment saying why. Rejected: keeping telemetry with a
  comment.
- **Comments on permission and environment changes.** One line each: why `--allow-env=LOG_TOKENS,LOG_STREAM` (npm:yaml
  reads them for debug output), and a named `setup-tools` step that adds `$HOME/.deno/bin` to `PATH` for the OpenSpec
  binary, instead of hiding it in "Install just".
- **checks.md.** The `pr-checklist` row says the body comes from the event payload in CI and from `--body-file` locally.
- **Self-contained tooling test.** The scenario-owner test builds its model with `repoWith()` and a synthetic feature,
  like its neighbor. Rejected: keeping `loadRepo('.')`, which breaks if `glab` is renamed.
- **Line length and workflow shell.** String literals and comments are split to 120 characters; the pinned schema URL
  import stays as a URL-only line. Shell in workflows and composite actions follows the shell style guide by choice
  (braced variables, multi-line `if`, `printf` for output with expansions, a comment on deliberate word splitting).
- **Refactor.** `checkFeatures` becomes per-concern helpers called in the same order, so problems print in the same
  order; `check_openspec.ts` gets a `generatedProblems()` function, and `exitCode` is inlined with its two tests
  rewritten against the main flow's result. Rejected: leaving the 185-line function.
- **`--posix` scaffold.** `scripts/new_feature.ts` accepts `--posix` and writes `install.sh` from the guide's POSIX
  skeleton shape (`#!/bin/sh`, `set -eu`, a header line for the POSIX reason, `${NAME-default}` defaults, `log`/`fail`
  with `printf`, a `validate_options` stub that makes options readonly, `main`) and POSIX tests that use a stand-in for
  `check`/`reportResults`, since `dev-container-features-test-lib` is bash. Rejected: documenting a manual conversion.

## Risks / Trade-offs

- [Stricter failures in release tagging and the bump check could stop a release on a transient git error] → The job can
  be rerun by dispatch; a silent skip is worse because it cannot be noticed.
- [Rebasing onto #69] → Both PRs touch the same scaffold code; this one waits for #69 to merge before its
  implementation.
- [The workflow shell restyle goes beyond the guide's formal scope] → Recorded as the maintainer's choice; the guide's
  scope does not change.
