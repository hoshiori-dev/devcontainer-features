# Proposal

## Why

The #52 audit of the administration tooling found no injection path and no secret exposure, but it found tooling that
hides unexpected failures, permission and environment changes nobody explains, a release job that exposes its write
token to more than it needs, local OpenSpec runs that send telemetry, documentation drift, and code that reads unlike
the rest of the repository (#70). Developers who audit this repository read the tooling as much as the features.

## What Changes

- Error handling surfaces unexpected failures: each catch that is meant for a missing file catches only that, and the
  release tagging and the version bump check fail instead of warning when they cannot read what they need.
- The `publish` job installs only the tools it uses, and jobs that only read the repository do not keep git credentials.
- Every place the tooling runs OpenSpec turns its telemetry off.
- Each permission and environment change carries its reason (`LOG_TOKENS`/`LOG_STREAM`, the Deno bin directory on
  `PATH`).
- The `pr-checklist` row of `.agents/knowledge/github/checks.md` matches the workflow.
- A tooling test stops depending on the real `glab` feature.
- Lines stay within 120 characters, shell embedded in workflows and composite actions follows the shell style guide, and
  long functions in `validate.ts` and `check_openspec.ts` are split, with output and exit codes unchanged.
- `just new-feature --posix` scaffolds a feature from the guide's POSIX skeleton.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`.

## Impact

`scripts/` (validate, check_openspec, tag_releases, docs, test_feature, new_feature, checks_test), `justfile`,
`.github/workflows/`, `.github/actions/`, and `.agents/knowledge/github/checks.md`. No file under `src/` or `test/`
changes, and no feature version changes. Implements https://github.com/hoshiori-dev/devcontainer-features/issues/70,
part of https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## Acceptance

### Becomes true

- An unexpected error in tag reading or in the base-commit reads of the version bump check ends the script with a
  message naming the file; an unexpected error in the cleanups named in #70 is reported with the file or command it
  concerns; a missing file is still handled as before.
- The `publish` job does not install just, and no read-only job leaves git credentials in its checkout.
- `just spec-check` and `scripts/check_openspec.ts` run OpenSpec with telemetry off.
- Every unexplained permission or environment change named in #70 has a comment giving its reason.
- `checks.md` describes how `pr-checklist` receives the body.
- The scenario-owner test builds its own model instead of loading the repository.
- No line in `scripts/`, the `justfile`, or the workflows exceeds 120 characters except a line holding only a URL, and
  embedded shell follows the shell style guide.
- `just new-feature --posix <id>` writes a POSIX `install.sh` and POSIX tests that pass shellcheck with
  `require-variable-braces`; `scripts/checks_test.ts` covers it.
- `just check` passes, and CI on the PR is green.

### Stays true

- The checks that `ci-gate` requires, their names, and what they accept are unchanged.
- Output and exit codes of `validate.ts` and `check_openspec.ts` on valid input are unchanged.
- `.devcontainer/`, `.pre-commit-config.yaml`, and `.editorconfig` are unchanged.
- No file under `src/` or `test/` changes, and no feature version changes.
- Repository content is English and carries no secrets, private data, or tool attribution.
