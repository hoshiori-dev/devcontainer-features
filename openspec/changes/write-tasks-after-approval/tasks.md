# Tasks

## 1. Artifact roles in the knowledge base

- [x] 1.1 Add an "Artifact roles" section to `.agents/knowledge/spec-workflow.md` after the Artifact map: the role of
      proposal, specs, design, and tasks, the invariant test, the information test, and the two Acceptance lists; verify
      by reading it against proposal.md - What Changes
- [x] 1.2 Align the rest of `spec-workflow.md`: Source of truth (acceptance of every change is its proposal's
      Acceptance, pointing to scenarios for feature behavior), Lifecycle (propose stops before `tasks.md`; tasks written
      after approval), Approval gates (the package is proposal, delta specs, and design when warranted; `tasks.md` does
      not exist yet), Specifications and issues (no `tasks.md` link in a draft); verify with
      `git grep -n "tasks.md" .agents/knowledge/spec-workflow.md` that no line contradicts the new timing

## 2. OpenSpec rules

- [x] 2.1 In `openspec/config.yaml`, add the approval condition as the first `rules.tasks` rule, and add
      `rules.proposal` and `rules.design` rules that state the roles briefly and point to the Artifact roles section;
      verify with `openspec instructions proposal|design|tasks --change write-tasks-after-approval --json` that each
      shows the new rules

## 3. Workflow skill, PR template, issue form

- [x] 3.1 In `.agents/skills/github-project-workflow/SKILL.md` step 3, open the draft without `tasks.md` (delete one a
      flow wrote early) and, after the reconciliation, write it through `openspec instructions tasks` before
      implementing; verify by reading the step against spec-workflow.md - Lifecycle
- [x] 3.2 In `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/03-task.yml`, `02-feature.yml`, and the
      synchronization list of `.agents/knowledge/github-workflow.md`, point acceptance to the proposal's Acceptance;
      verify `scripts/check_pr_body.ts` still passes on #7's body and `git grep -n "tasks.md" -- .github` shows no
      acceptance role left for `tasks.md`

## 4. Integration

- [x] 4.1 In a throwaway OpenSpec repository carrying this `openspec/config.yaml`, follow the generated propose skill
      for a small change and confirm it writes no `tasks.md`, ends the proposal with both Acceptance lists, and reports
      the package as ready
- [x] 4.2 Run `just check` and record each Acceptance item of proposal.md with its result in the PR's Validation section
