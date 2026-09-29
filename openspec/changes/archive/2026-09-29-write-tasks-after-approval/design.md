# Design

## Context

See proposal.md - Why. Information this change relies on, checked with OpenSpec 1.13.2 in a throwaway repository:

- `operations` in `config.yaml` accepts only `apply` and `archive`; there is no propose-time guidance.
- The propose flow reads `rules.<artifact>` for every artifact it writes. With a `rules.tasks` rule saying not to write
  `tasks.md` before approval, an agent following the generated propose skill wrote the proposal and specs, skipped
  `tasks.md`, and reported the package as ready.
- A change without `tasks.md` passes `openspec validate --strict`, so `just spec-check` stays green on a draft;
  `openspec status` shows `tasks` as not done until approval.
- The upstream `spec-driven` templates have no Acceptance section and give design the headings Context, Goals /
  Non-Goals, Decisions, Risks / Trade-offs; rules add to the instructions but cannot change the templates.
- `scripts/check_pr_body.ts` compares only the PR template's headings and its security item.

## Goals / Non-Goals

**Goals:**

- The roles live in one place, `spec-workflow.md`; `config.yaml` rules state them briefly and point there, as the
  config's own comment requires.
- The mechanism works through OpenSpec's own injection points only: no fork, no edited generated file.

**Non-Goals:**

- A CI check on when `tasks.md` appears; approval is conversational, so CI cannot see it.
- Changing the upstream templates or adding sections beyond the proposal's `## Acceptance`.

## Decisions

- **Guard the tasks step with a rule.** `rules.tasks` opens with the approval condition; OpenSpec injects it exactly
  where the flow would write the file. Alternative: a custom schema that drops `tasks` from the propose closure —
  rejected, apply requires `tasks`, and a fork freezes upstream instructions. Alternative: per-artifact
  `openspec instructions` calls in the workflow skill as the only control — rejected, an agent running `/opsx:propose`
  directly would bypass it; the skill still names the tasks step for after approval.
- **Deletion as fallback.** If a flow still writes `tasks.md` before approval, it is deleted before the commit.
- **Roles as a section of `spec-workflow.md`.** A short "Artifact roles" section after the Artifact map holds the four
  roles, the invariant test ("would it still have to hold under another approach?"), and the information test ("is it
  needed the next time this feature changes?"). Alternative: roles spelled out in each rule — rejected, it would restate
  the knowledge base in config and drift.
- **Acceptance in the proposal, as two lists.** "Becomes true" is the end state, "Stays true" the proposal-level
  invariants, each item checkable. Alternative: a separate `## Invariants` section — rejected, one heading keeps the
  proposal short and puts everything the result is checked against in one place. Alternative: acceptance in the design —
  rejected, a design is optional.
- **Contracts named, not restated.** For a change with specs, the proposal's Capabilities names the capabilities and its
  Acceptance points to their scenarios; after archive the proposal is frozen while specs live on, so a restated contract
  would go stale.
- **Design keeps upstream headings.** Goals / Non-Goals hold the chosen approach's own bounds, each with how it is
  checked; Context holds the change-scoped information. No new design sections.

## Risks / Trade-offs

- [The rules are guidance, not enforcement] → The fallback deletion and the package review catch a stray `tasks.md` or a
  misplaced role; the propose behavior is re-verified when this change is implemented.
- [Tasks written later drift from the approved package] → The second deliberation reviews the implementation against the
  proposal's Acceptance and the design's bounds.
- [An OpenSpec upgrade changes how rules reach the flow] → `spec-workflow.md` already requires re-verifying OpenSpec
  behavior on upgrade.
