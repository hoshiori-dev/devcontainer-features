# Proposal

Implements [#6](https://github.com/hoshiori-dev/devcontainer-features/issues/6).

## Why

OpenSpec's propose flow writes `tasks.md` together with the approval package, so every draft PR carries a task list that
the package gate does not review and that plans against a specification which may still change. The harness contradicts
itself about it: `.agents/knowledge/spec-workflow.md` says tasks are written after approval, while the GitHub workflow
skill pushes the generated file marked as after-approval. And a change without specs is accepted against its `tasks.md`,
so its acceptance is exactly the file the gate never sees.

## What Changes

- `openspec/config.yaml` `rules.tasks`: a first rule that `tasks.md` is written only after a maintainer closed the
  package gate in the current conversation; without that, the flow stops and reports the package as ready for review.
- `openspec/config.yaml` `rules.proposal` and `rules.design`: the proposal ends with an `## Acceptance` section —
  checkable criteria for a change without specs, a pointer to the delta specs' scenarios for a change with specs — and a
  design states its Goals as checkable criteria, so the approval package carries the acceptance the gate approves.
- `.agents/knowledge/spec-workflow.md`: the propose flow stops before `tasks.md`; the draft PR carries no `tasks.md`;
  the agent writes it after the package gate; a change without specs is accepted against its proposal and design (Source
  of truth, Lifecycle, Approval gates, Specifications and issues).
- `.agents/skills/github-project-workflow/SKILL.md`: step 3 opens the draft without `tasks.md`, and after the
  reconciliation the agent writes it through `openspec instructions tasks` before implementing.
- `.github/pull_request_template.md` and `.github/ISSUE_TEMPLATE/03-task.yml`: acceptance of a change without specs
  points to its proposal and design instead of `tasks.md`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Feature ids touched: none, so no version bump.
- Every future change opens its draft PR without `tasks.md`. The open change `define-upstream-reference-links` (#5)
  drops its generated `tasks.md` in its own PR.
- Acceptance of changes without specs moves from `tasks.md` to proposal and design; changes with specs keep their
  scenarios. The open change of #5 gains an `## Acceptance` section in its own PR.

## Acceptance

- Following the propose flow on a new change with this repository's `openspec/config.yaml` writes the proposal, delta
  specs, and design when warranted, writes no `tasks.md`, and reports the package as ready for review.
- `openspec instructions proposal`, `design`, and `tasks` for a change show the new rules.
- `spec-workflow.md`, the workflow skill, the PR template, and the Task issue form name the same timing for `tasks.md`
  and the same acceptance record for a change without specs; `git grep -n "tasks.md"` over them finds no contradiction.
- This change's own draft PR carries no `tasks.md`, and `just check` passes.
