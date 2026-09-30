# Design

## Context

- `feature-authoring.md` ("Layout", "Renaming and retiring") holds the per-feature file conventions. The generated
  `src/<id>/README.md` is described there as produced by `just docs`.
- `openspec/config.yaml` `rules.tasks` lists what a feature change's tasks cover: `install.sh`, the tests,
  compatibility, `NOTES.md`, the version bump, and `just docs`. OpenSpec injects this rule into
  `openspec instructions tasks`.
- `just spec-check` fails when a rule would not reach OpenSpec. A rule with a colon followed by a space must be quoted.

## Goals / Non-Goals

**Goals:**

- One statement of the convention, in `feature-authoring.md`. The task rule only names the item, so the two cannot
  drift. Checked by reading both after the edit.
- The task rule stays a plain string. Checked by `just spec-check`, whose config-rule check fails otherwise.

**Non-Goals:**

- Generating or checking the root list automatically. A script could compare the list with `src/`, but one row per
  feature PR is small enough to review by hand. Revisit if the list drifts.
- Editing the open feature drafts (issue Out of scope).

## Decisions

- **The row is part of the feature's own PR, not a follow-up.** A merged feature is published immediately, so the list
  is current from the first version.
  - Rejected: a README update after each release. It would be a separate PR with no owner.
- **The row holds the id, a link to `src/<id>/`, and one sentence.** Options and notes stay in the generated per-feature
  README, so the root list does not restate `devcontainer-feature.json`.
  - Rejected: a table with versions. Versions change with every release and would go stale.

## Risks / Trade-offs

- [A feature PR forgets the row] → The task rule puts it into every feature change's `tasks.md`, and review sees the
  README diff. Nothing enforces it mechanically (Non-Goals).
