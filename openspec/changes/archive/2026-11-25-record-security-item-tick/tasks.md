# Tasks

## 1. Skill

- [x] 1.1 In `.agents/skills/github-project-workflow/SKILL.md`, Publish gate: add the step stating that a pull request
      body carries the template's security checklist item ticked from the first draft on, that `pr-checklist` requires
      it, that the tick is written into the `body.md` under review and never after the verdict, and that every later
      edit of the body keeps it; verify by reading the step against the proposal's Acceptance, both lists.
- [x] 1.2 In the same file, Take work, the step that opens the draft pull request: point to that rule; verify that the
      step read alone says the item must be ticked.
- [x] 1.3 Verify the rule works as written: tick only the security item of `.github/pull_request_template.md` in a
      scratch copy and run `scripts/check_pr_body.ts --template .github/pull_request_template.md --body-file <copy>`; it
      passes, and the unedited template fails.

## 2. Checks map

- [x] 2.1 In `.agents/knowledge/github/checks.md`, Reading a run: name the causes of a failed `pr-checklist` run (a
      template heading missing, or the security item missing, reworded, or unticked) and point to the skill; verify the
      rule itself is stated in the skill only.
- [x] 2.2 Check `CONTRIBUTING.md` against its overview; verify it restates nothing this change makes stale, and leave it
      unchanged if so.

## 3. Integration

- [x] 3.1 Verify `scripts/check_pr_body.ts`, `.github/workflows/pr.yml`, `.github/pull_request_template.md`, and
      `.agents/knowledge/github-workflow.md` are unchanged against `main`.
- [x] 3.2 Run `just check` and record the result in the PR's Validation section.
