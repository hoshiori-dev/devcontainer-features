# Proposal

Implements [#6](https://github.com/hoshiori-dev/devcontainer-features/issues/6).

## Why

OpenSpec's propose flow writes `tasks.md` together with the approval package, so every draft PR carries a task list that
the package gate does not review and that plans against a specification which may still change. The harness contradicts
itself about it: `.agents/knowledge/spec-workflow.md` says tasks are written after approval, while the GitHub workflow
skill pushes the generated file marked as after-approval. A change without specs is even accepted against its
`tasks.md`, the one file the gate never sees. Behind both lies an undefined split between the artifacts: nothing says
which of proposal, specs, design, and tasks owns the goal, the acceptance, the contract, the invariants, or the
information a change relies on, so each change places them differently.

## What Changes

- Each artifact of a change has one defined role, stated in `spec-workflow.md` and injected by `openspec/config.yaml`
  `rules`:
  - **proposal** — the end state: why, the goal, what changes, the capabilities whose contracts change (named, never
    restated), and the acceptance of the result;
  - **specs** — the executable contract of feature behavior and its scenarios;
  - **design** — how the end state is reached: the approaches discussed, the decisions and rejected alternatives, the
    constraints and invariants of the chosen approach, and the information needed only for this change;
  - **tasks** — the implementation steps, written after the package gate, each with its own verification.
- An invariant that must hold under any approach belongs to the proposal; one that holds only because of the chosen
  approach belongs to the design. Information still needed the next time the feature changes goes to its spec, not the
  design.
- The proposal's `## Acceptance` has two checkable lists, "Becomes true" and "Stays true"; for a change with specs it
  points to the delta specs' scenarios for behavior instead of restating them.
- `tasks.md` is written only after a maintainer closes the package gate; the draft PR carries only the approval package,
  and the workflow skill writes tasks through `openspec instructions tasks` after the reconciliation.
- A change without specs is accepted against its proposal's Acceptance. The PR template and the Task issue form say so.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `openspec/config.yaml` (`rules.proposal`, `rules.design`, `rules.tasks`), `.agents/knowledge/spec-workflow.md`,
  `.agents/skills/github-project-workflow/SKILL.md`, `.github/pull_request_template.md`,
  `.github/ISSUE_TEMPLATE/03-task.yml`.
- Feature ids touched: none, so no version bump.
- The open change `define-upstream-reference-links` (#5) follows these roles in its own PR.

## Acceptance

**Becomes true:**

- Following the propose flow on a new change with this repository's `openspec/config.yaml` writes the proposal, the
  delta specs, and the design when warranted, writes no `tasks.md`, and reports the package as ready for review.
- `openspec instructions proposal|design|tasks --json` for a change shows rules that assign the roles above, including
  the two Acceptance lists and the approval condition for `tasks.md`.
- `spec-workflow.md` states each artifact's role, the test that places an invariant, and the test that places
  information; the workflow skill, the PR template, and the Task issue form agree with it on when `tasks.md` is written
  and what a change without specs is accepted against.

**Stays true:**

- Gate ownership, the second deliberation, and the archive command are unchanged.
- Feature behavior stays specified only in `openspec/specs/` and delta specs.
- OpenSpec's generated skills and commands are not edited; `just check` passes.
