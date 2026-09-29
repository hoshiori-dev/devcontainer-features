# Design

## Context

See proposal.md - Why. OpenSpec 1.13.2, checked in a throwaway repository: `operations` in `config.yaml` accepts only
`apply` and `archive`, so there is no propose-time guidance; the propose flow reads `rules.<artifact>` for every
artifact it writes; with a `rules.tasks` rule saying not to write `tasks.md` before approval, an agent following the
generated propose skill wrote the proposal and specs, skipped `tasks.md`, and reported the package as ready. A change
without `tasks.md` passes `openspec validate --strict`, so `just spec-check` stays green on a draft; `openspec status`
shows `tasks` as not done, which is the expected state until approval.

## Goals / Non-Goals

**Goals:**

- A draft PR's change directory holds no `tasks.md` — checked on this change's own draft and in a propose run.
- `tasks.md` first appears in a commit after the maintainer's "spec approved" in the conversation, written from
  `openspec instructions tasks` — checked when this change is implemented.
- Every proposal has an `## Acceptance` section and every design states checkable Goals — checked by the injected rules
  (`openspec instructions proposal|design --json`) and by this change's own artifacts.

**Non-Goals:**

- A CI check on when `tasks.md` appears; approval is conversational, so CI cannot see it.
- Changing gate ownership, the second deliberation, or the archive.

## Decisions

- **Guard the tasks step with a rule.** `rules.tasks` opens with the approval condition; OpenSpec injects it exactly
  where the flow would write the file, and the generated skills stay untouched (they are regenerated, never edited).
  Alternative: a custom schema that drops `tasks` from the propose closure — rejected, apply requires `tasks`, and a
  fork freezes upstream instructions. Alternative: replacing propose with per-artifact `openspec instructions` calls in
  the workflow skill — rejected as the primary control, since an agent running `/opsx:propose` directly would bypass it;
  the skill still names the tasks step for after approval.
- **Deletion as fallback.** If a flow still writes `tasks.md` before approval, the file is deleted before the commit; a
  draft never carries it.
- **Acceptance of a change without specs is its proposal and design.** The proposal states the goal and what changes,
  the design states the bounds; both pass the package gate. Tasks are implementation detail, and each task still states
  its own verification.
- **The approval package states acceptance explicitly.** The proposal ends with `## Acceptance`: checkable criteria for
  a change without specs; for a change with specs, one line pointing to the delta specs' scenarios, which stay the only
  source (never restated). A design states its Goals as checkable criteria. The rules go in `rules.proposal` and
  `rules.design`; the templates stay upstream's. Alternative: acceptance only in `design.md` — rejected, a design is
  optional, a proposal is not.
- **Checklist wording follows the acceptance.** The PR template's checklist and the Task issue form point to proposal
  and design for a change without specs; `check_pr_body.ts` compares only headings and the security item, so it needs no
  change.

## Risks / Trade-offs

- [The rule is guidance, not enforcement] → The fallback deletion and the draft review catch a stray `tasks.md`; the
  behavior was observed once and is re-verified in this change's validation.
- [Tasks written later can drift from the approved design] → The second deliberation reviews the implementation against
  proposal and design, and tasks change nothing they fix.
- [An OpenSpec upgrade changes how rules reach the flow] → `spec-workflow.md` already requires re-verifying OpenSpec
  behavior on upgrade.
