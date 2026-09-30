# Proposal

Implements [#8](https://github.com/hoshiori-dev/devcontainer-features/issues/8).

## Why

OpenSpec reads `openspec/config.yaml` field by field and replaces an invalid field with a warning. When one entry of
`rules.<artifact>` is not a string — an unquoted rule containing a colon followed by a space parses as a YAML mapping —
OpenSpec 1.13.2 prints `Rules for '<artifact>' must be an array of strings, ignoring this artifact's rules` to stderr
and injects none of that artifact's rules, while `openspec validate --all --strict` still exits 0. The project's rules
are how its conventions reach every artifact an agent writes, so losing a whole rule set silently defeats them; it
happened once already while writing a rule for #5 and was caught only by reading the injected instructions by hand.

## What Changes

- `just spec-check` — and so `just check` and the CI `spec` job — fails when `openspec/config.yaml` holds a rule
  OpenSpec would drop, naming the artifact and the entry:
  - `rules` is present but not a mapping of artifact ids to lists;
  - a `rules.<artifact>` value is not a list;
  - an entry of a `rules.<artifact>` list is not a string, or is an empty string.
- A `config.yaml` that cannot be read or parsed as YAML fails the same check with the parser's message.
- The failure message says how to fix the usual cause: quote the rule so YAML reads it as a string.
- `.agents/knowledge/spec-workflow.md` (Artifact operations) and the `spec` row of `.agents/knowledge/github/checks.md`
  say that `just spec-check` also checks the config's rules.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `scripts/check_openspec.ts` (already run by `just spec-check`), `scripts/checks_test.ts`, `justfile` (the
  `spec-check` recipe's comment), `.agents/knowledge/spec-workflow.md`, `.agents/knowledge/github/checks.md`.
- Dependencies: a pinned YAML parser import in `scripts/check_openspec.ts` (see design).
- Feature ids touched: none, so no version bump. No test-infrastructure path changes, so CI selects no feature.

## Acceptance

**Becomes true:**

- With an unquoted rule containing a colon followed by a space added under `rules.specs` in a local copy of
  `config.yaml`, `just spec-check` exits non-zero with a message naming `rules.specs` and the entry's position;
  restoring the file makes it pass.
- Unit tests in `just scripts-check` cover each problem listed under What Changes and a valid rules block.
- The current `openspec/config.yaml` passes `just spec-check`.

**Stays true:**

- Every rule in the current `config.yaml` stays as it is; this change rewrites none (the issue's Out of scope).
- Fields other than `rules` (`schema`, `context`, `operations`) are not checked by this change.
- The generated-files check in `scripts/check_openspec.ts` behaves as before, and `just spec-check` still runs
  `openspec validate --all --strict`.
- `just check` passes, and every required check passes on this PR.
