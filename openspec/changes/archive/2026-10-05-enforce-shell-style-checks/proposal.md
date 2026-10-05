# Proposal

## Why

`.agents/knowledge/shell-style.md` relies on two optional shellcheck checks, `require-variable-braces` and
`require-double-brackets`, but `just check`, the pre-commit hook, and the `lint` job run shellcheck without them, so the
guide asks every author to run them by hand. The ten feature restyles (#84 to #93) are merged, and every tracked `*.sh`
passes both checks, so the repository can now enforce them and close #52.

## What Changes

- A `.shellcheckrc` at the repository root enables `require-variable-braces` and `require-double-brackets`. shellcheck
  reads it wherever it runs: `just lint` (and so `just check` and the `lint` job) and the pre-commit hook.
- The guide's sentence that tells authors to run the two checks by hand until the restyle adds a `.shellcheckrc` is
  replaced by one that says `just check` enforces them.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`.

## Impact

`.shellcheckrc` (new) and `.agents/knowledge/shell-style.md`. No file under `src/` or `test/` changes, and no feature
version changes. The `lint` check becomes stricter: a shell script that leaves a variable unbraced, or a bash script
that tests with `[ … ]`, now fails `just check`, the pre-commit hook, and CI. The draft pull requests that add features
before the guide (#31, #32, #34) fail `lint` once they include this change, until their scripts follow the guide.
`.pre-commit-config.yaml` and the workflows are not edited. Closes
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## Acceptance

### Becomes true

- `shellcheck` run with no options on a script that has an unbraced variable reports SC2250, and on a bash script that
  uses `[ … ]` reports SC2292.
- `just check` passes on the branch with the `.shellcheckrc` in place and no other file under `src/` or `test/` changed.
- The guide no longer asks authors to run the two optional checks by hand.

### Stays true

- No file under `src/` or `test/` changes, and no feature version changes.
- POSIX `sh` scripts keep testing with `[ … ]`: `require-double-brackets` applies only to bash scripts.
- `.pre-commit-config.yaml`, `.devcontainer/`, and the workflows are unchanged.
