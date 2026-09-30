# Proposal

Implements [#2](https://github.com/hoshiori-dev/devcontainer-features/issues/2).

## Why

A maintainer applied the remote settings that `.agents/knowledge/github/platform-settings.md` lists as intended, on
2026-09-30, and each one reads back as intended. The knowledge base still describes them as conventions "not yet
applied", so an agent reading it would treat merge blocks, squash-only merging, and required checks as advisory, and
would find no readback for the settings it was told only the UI can show.

## What Changes

- Every applied row of `platform-settings.md` — merge methods, ruleset `main`, ruleset bypass actors, legacy branch
  protection, Actions, secret scanning, push protection, code scanning, private vulnerability reporting, Dependabot
  alerts — reads "Enforced (2026-09-30)", and its Verify column names a readback that works with a maintainer's token.
  The "Last verified" line records the 2026-09-30 readback.
- `platform-settings.md` records the ruleset parameters GitHub adds on its own, so a readback does not look like drift:
  the additional approval for unattributed Copilot pull requests is on by default, and the ruleset allows all three
  merge methods while the repository setting allows only squash.
- The enforcement register and the `main` branch row of `.agents/knowledge/git-workflow.md`, its merge-method
  enforcement note, and the required-checks note in `.agents/knowledge/github/checks.md` state the rules as enforced.
- No intended state changes. SHA pinning of actions is recorded separately under #9.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `.agents/knowledge/github/platform-settings.md`, `.agents/knowledge/git-workflow.md`,
  `.agents/knowledge/github/checks.md`.
- Feature ids touched: none, so no version bump.
- Remote settings: none changed by this change; they were applied by a maintainer before it.

## Acceptance

**Becomes true:**

- Each applied row of `platform-settings.md` reads "Enforced (2026-09-30)", and running its readback returns the
  intended state.
- The enforcement register in `git-workflow.md` marks PR-only changes, the required checks, and squash-only merging with
  branch deletion as enforced, and no file under `.agents/knowledge/` still calls the `main` ruleset or the merge
  settings unapplied.
- This pull request, once marked ready, cannot merge while `spec-archived` is red: GitHub reports it as blocked.

**Stays true:**

- The intended state of every row is unchanged; GHCR packages and organization issue types stay out of scope.
- Remote settings remain maintainer actions; the agent authority policy is unchanged.
- `just check` passes.
