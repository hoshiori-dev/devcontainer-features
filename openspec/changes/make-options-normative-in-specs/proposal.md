# Proposal

Implements [#45](https://github.com/hoshiori-dev/devcontainer-features/issues/45).

## Why

A feature's options are the contract its consumers write into `devcontainer.json`, and a changed default reaches every
consumer who omits the option — the Versions table in `.agents/knowledge/feature-authoring.md` makes it a MAJOR bump.
Yet `rules.specs` in `openspec/config.yaml` keeps option types and defaults out of specs, so a change that only flips a
default has no spec text to modify, the Information test in `.agents/knowledge/spec-workflow.md` (information needed
again the next time the feature changes goes to its spec) is contradicted, and the approval package has no place for a
default while `devcontainer-feature.json` does not exist yet. The rule dates from the harness bootstrap and records no
rationale; no feature has merged yet, so no main spec needs migrating.

## What Changes

- A feature's spec states each option as its own requirement — an Option requirement — giving the option's name, type,
  default, and `enum` values. Its scenarios cover what the option's values do.
- `.agents/knowledge/spec-workflow.md` defines the Option requirement format, and its Source of truth table makes the
  spec's Option requirements the owner of option names, types, defaults, and `enum` values.
  `src/<id>/devcontainer-feature.json` implements them and keeps sole ownership of `proposals` and `description`. A
  change's design may list the options that change touches — the one restatement the table allows, frozen at archive,
  with the delta spec winning where the two differ. The package gate's review names each option's requirement.
- `rules.specs` in `openspec/config.yaml` points to that format instead of leaving types and defaults to
  `devcontainer-feature.json`; `rules.design` asks a design to describe, in a table, every option the change adds,
  changes, renames, or removes — name, type, default, `enum` or `proposals`, and meaning — with the reason for each
  default and the rejected option shapes.
- `just spec-check` — and so `just check` and the CI `spec` job — fails when a feature's options in
  `devcontainer-feature.json` differ from its spec, naming the feature, the option, and the field; an option change
  counts from the moment its implementation starts. It also fails when an Option requirement in a main spec or an active
  change cannot be read, or when OpenSpec cannot apply a change the comparison needs.
- `just new-feature <id>` takes the new feature's options from its change's delta spec instead of scaffolding a fixed
  `version` option.
- `.agents/knowledge/spec-workflow.md` (Artifact operations), `.agents/knowledge/feature-authoring.md` (Metadata,
  Layout), `.agents/knowledge/github/checks.md` (the `spec` row), and the `justfile` comment of `spec-check` say so.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `openspec/config.yaml`, `.agents/knowledge/spec-workflow.md`, `.agents/knowledge/feature-authoring.md`,
  `.agents/knowledge/github/checks.md`, `justfile`, `scripts/check_openspec.ts`, `scripts/new_feature.ts`, a shared
  parser under `scripts/lib/` with its tests beside it, and `scripts/checks_test.ts`.
- Feature ids touched: none, so no version bump. `scripts/lib/` is a test-infrastructure path, so CI selects the canary
  set, which is empty, so no feature is tested.
- The open feature drafts adopt Option requirements in their own delta specs before their package gates close; a draft
  whose gate already closed needs the maintainer to confirm the added requirements. This PR edits none of them.

## Acceptance

**Becomes true:**

- `.agents/knowledge/spec-workflow.md` defines the Option requirement format, and its Source of truth table names the
  spec's Option requirements as the owner of option names, types, defaults, and `enum` values, and
  `devcontainer-feature.json` as the owner of `proposals` and `description`; it lets a change's design list the options
  that change touches, frozen at archive, with the delta spec winning where the two differ.
- No rule in `openspec/config.yaml` and no knowledge file tells authors to leave option types or defaults out of specs;
  `rules.specs` points to the Option requirement format, and `rules.design` asks for the table of the options a change
  touches (name, type, default, `enum` or `proposals`, meaning) with the reasons behind each default.
- In a copy of the repository holding a feature whose spec and `devcontainer-feature.json` agree, `just spec-check`
  passes; changing the default, the type, or the `enum` values on one side, or adding an option to one side only, makes
  it fail with a message naming the feature, the option, and the field.
- In the same copy, an active change that modifies an Option requirement and has no `tasks.md` does not fail the check
  while `devcontainer-feature.json` still matches the main spec; once the change has a `tasks.md`, the check compares
  `devcontainer-feature.json` with the spec as that change would archive it.
- A feature with a spec but no `src/<id>/` yet is not compared, and neither is a `src/<id>/` without a spec, which
  `just validate` already reports.
- An Option requirement missing its type or default, or holding a value that cannot be read, fails `just spec-check`
  with a message naming the requirement, whether it sits in a main spec or in an active change's delta, with or without
  a `tasks.md`.
- A change that OpenSpec refuses to archive in the check's copy fails `just spec-check` with a message naming the change
  and OpenSpec's reason.
- Unit tests in `just scripts-check` cover reading Option requirements and comparing them with option metadata.
- `just new-feature <id>` for a feature whose active change declares options produces a `devcontainer-feature.json`
  whose options pass the comparison.

**Stays true:**

- `proposals`, `description`, and the environment-variable mapping of options are not stated in specs; the generated
  README keeps rendering options from `devcontainer-feature.json`.
- The existing checks of `just spec-check` behave as before: strict validation, the config rules check, and the
  generated-files check.
- `just spec-check` changes nothing in the working tree, and it sees changes that are not committed yet, untracked files
  included.
- No row of the Source of truth table other than the options row gains an exception to "never restates the fact".
- The approval gates keep their owners, modes, and order.
- No file of an open feature draft changes in this PR, and no feature version changes.
- `just check` passes, and every required check passes on this PR.
