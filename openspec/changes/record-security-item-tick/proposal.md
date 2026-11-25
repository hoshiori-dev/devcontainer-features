# Proposal

## Why

`pr-checklist` is a required check, and it fails while the security item of the pull request template's checklist is
missing, reworded, or unticked — on a draft too. Nothing an agent reads before opening a pull request says so: the
`github-project-workflow` skill builds the draft body from the template without mentioning the tick, and `checks.md`
maps the job to its script without saying what the script requires. Drafts opened by following the skill therefore fail
the check on their first run, and the rule is learned from the red check each time. This change implements
[issue #209](https://github.com/hoshiori-dev/devcontainer-features/issues/209).

## What Changes

- The `github-project-workflow` skill states, in its Publish gate, that a pull request body carries the security
  checklist item ticked from the first draft on, that the tick is written into the body the gate reviews, and that every
  later edit of the body keeps it.
- The skill's step that opens the draft pull request points to that rule.
- `checks.md` names what makes a `pr-checklist` run fail and where the fix is described.

## Capabilities

### New Capabilities

None. This is a harness change with `skip_specs: true`.

### Modified Capabilities

None. No feature's installation contract changes.

## Impact

- Expected scope: `.agents/skills/github-project-workflow/SKILL.md` and `.agents/knowledge/github/checks.md`.
  `CONTRIBUTING.md` is checked against its overview and revised only if it became stale.
- No feature id changes; no feature needs a version bump.
- No change to `scripts/check_pr_body.ts`, `.github/workflows/pr.yml`, the pull request template, the required checks,
  or any other workflow. No new runtime or dependency.

## Acceptance

**Becomes true:**

- The skill's Publish gate states that a pull request body carries the template's security checklist item ticked from
  the first draft on, names `pr-checklist` as the check that requires it, and says that the tick is written into the
  body under review and reaches GitHub only on a passing verdict.
- The skill's step that opens the draft pull request refers to that rule, so an agent reading only that step learns that
  the item must be ticked.
- `checks.md` lists the causes of a failed `pr-checklist` run — a template heading missing, or the security item
  missing, reworded, or unticked — and points to the skill for the fix.
- A body built from the template by following the skill, with no other edit, passes
  `scripts/check_pr_body.ts --template .github/pull_request_template.md --body-file <body>`.
- `just check` passes.

**Stays true:**

- The published body is byte-identical to the body the publish gate reviewed: the tick is never added after the verdict.
- A tick is published only with a passing verdict of the publish gate; the rule never tells an author to tick the item
  without that review.
- `pr-checklist` requires what it required before: the template's headings and the one security item. No other checklist
  item becomes required, and the check, the workflow, and the template are unchanged.
- The rule which checklist items a ready pull request ticks (`github-workflow.md`) is unchanged.
